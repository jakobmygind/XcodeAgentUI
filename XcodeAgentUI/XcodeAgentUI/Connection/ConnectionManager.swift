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
                return a.localizedDescription == b.localizedDescription
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
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // Validate profile
        guard profile.isConfigured else {
            state = .failed(.invalidProfile(profile))
            return
        }
        
        state = .connecting(profile.kind)
        
        do {
            // Perform health check
            let health = try await performHealthCheck(profile: profile)
            
            // Verify protocol version
            guard health.protocolVersion >= Self.minimumProtocolVersion else {
                throw ConnectionError.backendVersionMismatch(
                    backend: health.version,
                    required: Self.minimumProtocolVersion
                )
            }
            
            // Update last connected timestamp
            let latency = profile.lastLatencyMs ?? 0
            try? await profileStore.updateLastConnected(id: profile.id, latencyMs: latency)
            
            // Mark as connected
            activeProfile = profile
            state = .connected(profile)
            feedMode = .websocket
            
        } catch let error as ConnectionError {
            state = .failed(error)
        } catch {
            state = .failed(.healthCheckFailed(profile.healthURL, 0))
        }
    }
    
    /// Connect using automatic fallback logic
    func connectWithFallback() async {
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        do {
            let profiles = try await profileStore.allProfiles()
            
            guard !profiles.isEmpty else {
                state = .failed(.noDefaultProfile)
                return
            }
            
            // Get prioritized list
            let prioritized = prioritizeProfiles(profiles)
            
            // Try each profile in order
            for profile in prioritized {
                guard profile.isConfigured else { continue }
                
                state = .connecting(profile.kind)
                
                do {
                    let health = try await performHealthCheck(profile: profile)
                    
                    guard health.protocolVersion >= Self.minimumProtocolVersion else {
                        continue  // Try next profile on version mismatch
                    }
                    
                    // Update last connected
                    let latency = profile.lastLatencyMs ?? 0
                    try? await profileStore.updateLastConnected(id: profile.id, latencyMs: latency)
                    
                    // Success!
                    activeProfile = profile
                    state = .connected(profile)
                    feedMode = .websocket
                    return
                    
                } catch {
                    // Continue to next profile
                    continue
                }
            }
            
            // All profiles failed
            state = .failed(.allProfilesFailed)
            
        } catch {
            state = .failed(.allProfilesFailed)
        }
    }
    
    /// Connect to the fastest responding profile (parallel probe)
    func connectToFastest() async {
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        reconnectTask = nil
        
        do {
            let profiles = try await profileStore.allProfiles()
                .filter { $0.isConfigured }
            
            guard !profiles.isEmpty else {
                state = .failed(.noDefaultProfile)
                return
            }
            
            // Probe all profiles in parallel
            let results = await withTaskGroup(of: (ConnectionProfile, Int)?.self) { group in
                for profile in profiles {
                    group.addTask { [weak self] in
                        guard let self = self else { return nil }
                        let start = ContinuousClock().now
                        do {
                            _ = try await self.performHealthCheck(profile: profile)
                            let duration = ContinuousClock().now - start
                            let latencyMs = Int(duration.components.attoseconds / 1_000_000_000_000_000)
                            return (profile, latencyMs)
                        } catch {
                            return nil
                        }
                    }
                }
                
                var results: [(ConnectionProfile, Int)] = []
                for await result in group {
                    if let r = result {
                        results.append(r)
                    }
                }
                return results
            }
            
            // Connect to the fastest
            guard let (fastest, latency) = results.min(by: { $0.1 < $1.1 }) else {
                state = .failed(.allProfilesFailed)
                return
            }
            
            await connect(to: fastest)
            
            // Update latency
            try? await profileStore.updateLastConnected(id: fastest.id, latencyMs: latency)
            
        } catch {
            state = .failed(.allProfilesFailed)
        }
    }
    
    /// Disconnect from the current backend
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        activeProfile = nil
        state = .disconnected
        feedMode = .offline
    }
    
    /// Handle WebSocket failure by falling back to polling
    func handleWebSocketFailure(reason: String) {
        guard case .connected(let profile) = state else { return }
        
        feedMode = .polling(5)  // Poll every 5 seconds
        
        // Start background reconnection attempts
        startReconnection(profile: profile)
    }
    
    /// Mark the current WebSocket as recovered
    func markWebSocketRecovered() {
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
        
        var request = URLRequest(url: profile.healthURL, timeoutInterval: timeout)
        
        // Add authorization if needed
        if let token = try? await profileStore.resolveToken(for: profile) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ConnectionError.healthCheckFailed(profile.healthURL, 0)
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw ConnectionError.authenticationFailed(profile.healthURL)
                }
                throw ConnectionError.healthCheckFailed(profile.healthURL, httpResponse.statusCode)
            }
            
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            return health
            
        } catch is URLError {
            throw ConnectionError.healthCheckTimeout(profile.healthURL, timeout)
        } catch is DecodingError {
            throw ConnectionError.decodingError("Invalid health response format")
        } catch let error as ConnectionError {
            throw error
        } catch {
            throw ConnectionError.healthCheckFailed(profile.healthURL, 0)
        }
    }
    
    private func startReconnection(profile: ConnectionProfile) {
        reconnectTask?.cancel()
        
        reconnectTask = Task { [weak self] in
            for attempt in 1...(self?.maxReconnectAttempts ?? 5) {
                guard let self = self else { return }
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.state = .reconnecting(lastProfile: profile, attempt: attempt)
                }
                
                // Exponential backoff
                let delay = min(
                    (self.reconnectDelayBase * pow(2.0, Double(attempt - 1))),
                    self.maxReconnectDelay
                )
                
                try? await Task.sleep(for: .seconds(delay))
                
                guard !Task.isCancelled else { return }
                
                // Try to reconnect
                do {
                    let health = try await self.performHealthCheck(profile: profile)
                    guard health.protocolVersion >= Self.minimumProtocolVersion else {
                        continue
                    }
                    
                    // Success!
                    await MainActor.run {
                        self.feedMode = .websocket
                        self.state = .connected(profile)
                    }
                    return
                    
                } catch {
                    // Continue to next attempt
                    continue
                }
            }
            
            // All attempts failed, try fallback
            guard !Task.isCancelled else { return }
            await self?.connectWithFallback()
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
