import Foundation
import Observation

/// Manages connections to OpenClaw backends with automatic fallback
@Observable
@MainActor
final class ConnectionManager: Sendable {
    // MARK: - Types
    
    /// Current connection state
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting(ProfileKind)
        case connected(ConnectionProfile)
        case reconnecting(lastProfile: ConnectionProfile, attempt: Int)
        case failed(ConnectionError)
        
        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected):
                return true
            case (.connecting(let a), .connecting(let b)):
                return a == b
            case (.connected(let a), .connected(let b)):
                return a.id == b.id
            case (.reconnecting(let a, let b), .reconnecting(let c, let d)):
                return a.id == c.id && b == d
            case (.failed(let a), .failed(let b)):
                // Compare error types, not descriptions
                return a.isEqual(to: b)
            default:
                return false
            }
        }
        
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
        
        var isConnecting: Bool {
            switch self {
            case .connecting, .reconnecting:
                return true
            default:
                return false
            }
        }
    }
    
    /// Feed mode for real-time updates
    enum FeedMode: Equatable, Sendable {
        case websocket       // real-time push — ideal
        case polling(Int)    // HTTP polling interval in seconds — fallback
        case offline         // no connection — show last known state
    }
    
    // MARK: - Properties
    
    /// Current connection state
    private(set) var state: ConnectionState = .disconnected
    
    /// Currently active profile
    private(set) var activeProfile: ConnectionProfile?
    
    /// Current feed mode
    private(set) var feedMode: FeedMode = .offline
    
    /// The profile store for persistence
    private let profileStore: ProfileStore
    
    /// URL session for HTTP requests
    private let urlSession: URLSession
    
    /// Minimum protocol version required by this client
    static let minimumProtocolVersion = 1
    
    /// Default timeouts for different profile kinds
    private let timeouts: [ProfileKind: TimeInterval] = [
        .local: 1.0,
        .tailscale: 5.0,
        .custom: 5.0
    ]
    
    /// Reconnection configuration
    private let maxReconnectAttempts = 5
    private let reconnectDelayBase: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    
    /// Task for ongoing reconnection attempts
    private var reconnectTask: Task<Void, Never>?
    
    /// Logger for connection events
    private let logger = ConnectionLogger()
    
    // MARK: - Initialization
    
    init(profileStore: ProfileStore = .shared, urlSession: URLSession = .shared) {
        self.profileStore = profileStore
        self.urlSession = urlSession
    }
    
    nonisolated deinit {
        reconnectTask?.cancel()
    }
    
    // MARK: - Public API
    
    /// Connect to a specific profile
    func connect(to profile: ConnectionProfile) async {
        logger.log(.info, "Connecting to profile: \(profile.name) (\(profile.endpointDescription))")
        
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // Validate profile
        guard profile.isConfigured else {
            logger.log(.error, "Profile \(profile.name) is not configured")
            state = .failed(.invalidProfile(profile))
            return
        }
        
        state = .connecting(profile.kind)
        
        do {
            // Perform health check with latency measurement
            let (health, latencyMs) = try await performHealthCheckWithLatency(profile: profile)
            
            // Verify protocol version
            guard health.protocolVersion >= Self.minimumProtocolVersion else {
                logger.log(.error, "Backend version mismatch: got \(health.protocolVersion), need \(Self.minimumProtocolVersion)")
                throw ConnectionError.backendVersionMismatch(
                    backend: health.version,
                    required: Self.minimumProtocolVersion
                )
            }
            
            // Update last connected timestamp
            try? await profileStore.updateLastConnected(id: profile.id, latencyMs: latencyMs)
            
            // Mark as connected
            activeProfile = profile
            state = .connected(profile)
            feedMode = .websocket
            
            logger.log(.info, "Successfully connected to \(profile.name) (latency: \(latencyMs)ms)")
            
        } catch let error as ConnectionError {
            logger.log(.error, "Connection failed: \(error.localizedDescription)")
            state = .failed(error)
        } catch {
            logger.log(.error, "Unexpected error: \(error.localizedDescription)")
            state = .failed(.healthCheckFailed(profile.healthURL, 0))
        }
    }
    
    /// Connect using automatic fallback logic
    func connectWithFallback() async {
        logger.log(.info, "Starting fallback connection sequence")
        
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        do {
            let profiles = try await profileStore.allProfiles()
            
            guard !profiles.isEmpty else {
                logger.log(.error, "No profiles configured")
                state = .failed(.noDefaultProfile)
                return
            }
            
            // Get prioritized list
            let prioritized = prioritizeProfiles(profiles)
            
            logger.log(.info, "Trying \(prioritized.count) profiles in order")
            
            // Try each profile in order
            for profile in prioritized {
                guard profile.isConfigured else {
                    logger.log(.debug, "Skipping unconfigured profile: \(profile.name)")
                    continue
                }
                
                state = .connecting(profile.kind)
                
                do {
                    let (health, latencyMs) = try await performHealthCheckWithLatency(profile: profile)
                    
                    guard health.protocolVersion >= Self.minimumProtocolVersion else {
                        logger.log(.warning, "Profile \(profile.name) has incompatible version \(health.protocolVersion)")
                        continue  // Try next profile on version mismatch
                    }
                    
                    // Update last connected
                    try? await profileStore.updateLastConnected(id: profile.id, latencyMs: latencyMs)
                    
                    // Success!
                    activeProfile = profile
                    state = .connected(profile)
                    feedMode = .websocket
                    logger.log(.info, "Connected to \(profile.name) via fallback (latency: \(latencyMs)ms)")
                    return
                    
                } catch {
                    logger.log(.warning, "Failed to connect to \(profile.name): \(error.localizedDescription)")
                    // Continue to next profile
                    continue
                }
            }
            
            // All profiles failed
            logger.log(.error, "All profiles failed to connect")
            state = .failed(.allProfilesFailed)
            
        } catch {
            logger.log(.error, "Failed to load profiles: \(error.localizedDescription)")
            state = .failed(.allProfilesFailed)
        }
    }
    
    /// Connect to the fastest responding profile (parallel probe)
    func connectToFastest() async {
        logger.log(.info, "Starting parallel probe for fastest connection")
        
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        do {
            let profiles = try await profileStore.allProfiles()
                .filter { $0.isConfigured }
            
            guard !profiles.isEmpty else {
                logger.log(.error, "No configured profiles available")
                state = .failed(.noDefaultProfile)
                return
            }
            
            logger.log(.info, "Probing \(profiles.count) profiles in parallel")
            
            // Probe all profiles in parallel
            let results = await withTaskGroup(of: ProbeResult.self) { group in
                for profile in profiles {
                    group.addTask {
                        await self.probeProfile(profile)
                    }
                }
                
                var results: [ProbeResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            
            // Find successful results sorted by latency
            let successfulResults = results
                .compactMap { result -> (profile: ConnectionProfile, latencyMs: Int)? in
                    if case .success(let profile, let latency) = result {
                        return (profile, latency)
                    }
                    return nil
                }
                .sorted { $0.latencyMs < $1.latencyMs }
            
            // Connect to the fastest
            guard let fastest = successfulResults.first else {
                logger.log(.error, "All profile probes failed")
                state = .failed(.allProfilesFailed)
                return
            }
            
            logger.log(.info, "Fastest profile: \(fastest.profile.name) (\(fastest.latencyMs)ms)")
            
            await connect(to: fastest.profile)
            
            // Update latency
            try? await profileStore.updateLastConnected(id: fastest.profile.id, latencyMs: fastest.latencyMs)
            
        } catch {
            logger.log(.error, "Failed to probe profiles: \(error.localizedDescription)")
            state = .failed(.allProfilesFailed)
        }
    }
    
    /// Disconnect from the current backend
    func disconnect() {
        logger.log(.info, "Disconnecting from \(activeProfile?.name ?? "unknown")")
        reconnectTask?.cancel()
        reconnectTask = nil
        activeProfile = nil
        state = .disconnected
        feedMode = .offline
    }
    
    /// Handle WebSocket failure by falling back to polling
    func handleWebSocketFailure(reason: String) {
        logger.log(.warning, "WebSocket failure: \(reason)")
        
        guard case .connected(let profile) = state else {
            logger.log(.debug, "Not in connected state, ignoring WebSocket failure")
            return
        }
        
        feedMode = .polling(5)  // Poll every 5 seconds
        
        // Start background reconnection attempts
        startReconnection(profile: profile)
    }
    
    /// Mark the current WebSocket as recovered
    func markWebSocketRecovered() {
        logger.log(.info, "WebSocket recovered")
        if case .connected = state {
            feedMode = .websocket
            reconnectTask?.cancel()
            reconnectTask = nil
        }
    }
    
    /// Get the authorization header for the active profile
    func authorizationHeader() async -> String? {
        guard let profile = activeProfile else { return nil }
        return try? await profileStore.resolveToken(for: profile)
    }
    
    // MARK: - Private Helpers
    
    /// Result of probing a single profile
    private enum ProbeResult: Sendable {
        case success(profile: ConnectionProfile, latencyMs: Int)
        case failure(profileId: UUID, error: ConnectionError)
    }
    
    /// Probe a single profile and return the result
    private func probeProfile(_ profile: ConnectionProfile) async -> ProbeResult {
        let startTime = Date()
        do {
            let health = try await performHealthCheck(profile: profile)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            
            guard health.protocolVersion >= Self.minimumProtocolVersion else {
                return .failure(profileId: profile.id, error: .backendVersionMismatch(
                    backend: health.version,
                    required: Self.minimumProtocolVersion
                ))
            }
            
            return .success(profile: profile, latencyMs: latencyMs)
        } catch let error as ConnectionError {
            return .failure(profileId: profile.id, error: error)
        } catch {
            return .failure(profileId: profile.id, error: .healthCheckFailed(profile.healthURL, 0))
        }
    }
    
    private func prioritizeProfiles(_ profiles: [ConnectionProfile]) -> [ConnectionProfile] {
        profiles.sorted { a, b in
            // 1. Default profile first
            if a.isDefault != b.isDefault { return a.isDefault }
            
            // 2. Then by kind priority
            if a.kind != b.kind { return a.kind.priority < b.kind.priority }
            
            // 3. Then by most recently connected
            let aDate = a.lastConnected ?? .distantPast
            let bDate = b.lastConnected ?? .distantPast
            return aDate > bDate
        }
    }
    
    private func performHealthCheck(profile: ConnectionProfile) async throws -> HealthResponse {
        let timeout = timeouts[profile.kind] ?? 5.0
        
        guard let healthURL = profile.healthURL else {
            throw ConnectionError.invalidProfile(profile)
        }
        
        var request = URLRequest(url: healthURL, timeoutInterval: timeout)
        
        // Add authorization if needed
        if let token = try? await profileStore.resolveToken(for: profile) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConnectionError.healthCheckFailed(healthURL, 0)
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw ConnectionError.authenticationFailed(healthURL)
                }
                throw ConnectionError.healthCheckFailed(healthURL, httpResponse.statusCode)
            }
            
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health
            
        } catch is URLError {
            throw ConnectionError.healthCheckTimeout(healthURL, timeout)
        } catch is DecodingError {
            throw ConnectionError.decodingError("Invalid health response format")
        } catch let error as ConnectionError {
            throw error
        } catch {
            throw ConnectionError.healthCheckFailed(healthURL, 0)
        }
    }
    
    private func performHealthCheckWithLatency(profile: ConnectionProfile) async throws -> (HealthResponse, Int) {
        let startTime = Date()
        let health = try await performHealthCheck(profile: profile)
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        return (health, latencyMs)
    }
    
    private func startReconnection(profile: ConnectionProfile) {
        reconnectTask?.cancel()
        
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            
            for attempt in 1...self.maxReconnectAttempts {
                // Check if task was cancelled
                guard !Task.isCancelled else {
                    self.logger.log(.debug, "Reconnection task cancelled")
                    return
                }
                
                self.logger.log(.info, "Reconnection attempt \(attempt)/\(self.maxReconnectAttempts)")
                
                await MainActor.run {
                    self.state = .reconnecting(lastProfile: profile, attempt: attempt)
                }
                
                // Exponential backoff
                let delay = min(
                    (self.reconnectDelayBase * pow(2.0, Double(attempt - 1))),
                    self.maxReconnectDelay
                )
                
                self.logger.log(.debug, "Waiting \(String(format: "%.1f", delay))s before retry")
                
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    self.logger.log(.debug, "Sleep interrupted")
                    return
                }
                
                guard !Task.isCancelled else {
                    self.logger.log(.debug, "Reconnection task cancelled after sleep")
                    return
                }
                
                // Try to reconnect
                do {
                    let health = try await self.performHealthCheck(profile: profile)
                    guard health.protocolVersion >= Self.minimumProtocolVersion else {
                        self.logger.log(.warning, "Version mismatch during reconnection")
                        continue
                    }
                    
                    // Success!
                    await MainActor.run {
                        self.logger.log(.info, "Reconnection successful")
                        self.feedMode = .websocket
                        self.state = .connected(profile)
                    }
                    return
                    
                } catch {
                    self.logger.log(.warning, "Reconnection attempt failed: \(error.localizedDescription)")
                    // Continue to next attempt
                    continue
                }
            }
            
            // All attempts failed, try fallback
            guard !Task.isCancelled else { return }
            self.logger.log(.error, "All reconnection attempts failed, trying fallback")
            await self.connectWithFallback()
        }
    }
}

// MARK: - Health Response

/// Response from the backend health endpoint
struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let protocolVersion: Int
    let timestamp: String
}

// MARK: - Connection Logger

/// Simple logger for connection events
private struct ConnectionLogger: Sendable {
    enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }
    
    func log(_ level: Level, _ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] [ConnectionManager] [\(level.rawValue)] \(message)")
    }
}
