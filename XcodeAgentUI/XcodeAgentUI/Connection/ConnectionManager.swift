import Foundation
import Observation

/// Manages connections to OpenClaw backends with fallback logic
@Observable
@MainActor
final class ConnectionManager {
    var state: ConnectionState = .disconnected
    var activeProfile: ConnectionProfile?
    var availableProfiles: [ConnectionProfile] = []
    
    /// Feed mode for real-time updates
    enum FeedMode: Equatable, Sendable {
        case websocket       // real-time push — ideal
        case polling(Int)    // HTTP polling interval in seconds — fallback
        case offline         // no connection — show last known state
    }
    
    var feedMode: FeedMode = .offline
    
    private let store: ProfileStore
    private var webSocket: BridgeWebSocket?
    private var reconnectTask: Task<Void, Never>?
    private var maxReconnectAttempts = 5
    private var probeResults: [UUID: ProbeResult] = [:]
    private let probeResultsLock = NSLock()
    
    /// Maximum number of concurrent probes to prevent overwhelming the system
    private let maxConcurrentProbes = 10
    
    init(store: ProfileStore = .shared, webSocket: BridgeWebSocket? = nil) {
        self.store = store
        self.webSocket = webSocket
    }
    
    // MARK: - Profile Management
    
    /// Load profiles from store
    func loadProfiles() async {
        do {
            availableProfiles = try await store.load()
        } catch {
            state = .failed(.discoveryFailed(error.localizedDescription))
        }
    }
    
    /// Connect to a specific profile with retry logic
    /// - Parameters:
    ///   - profile: The profile to connect to
    ///   - maxRetries: Maximum number of retry attempts (default: 0)
    func connect(to profile: ConnectionProfile, maxRetries: Int = 0) async {
        // Cancel any ongoing reconnection
        reconnectTask?.cancel()
        
        // Validate profile first
        do {
            try profile.validate()
        } catch let error as ConnectionProfile.ValidationError {
            state = .failed(.discoveryFailed(error.localizedDescription ?? "Invalid profile"))
            return
        } catch {
            state = .failed(.discoveryFailed("Profile validation failed"))
            return
        }
        
        state = .connecting(profile.kind)
        
        var lastError: ConnectionError?
        
        for attempt in 0...maxRetries {
            // Check for cancellation
            guard !Task.isCancelled else {
                state = .disconnected
                return
            }
            
            do {
                // Probe the profile first
                let result = await probe(profile)
                guard result.success else {
                    throw result.error ?? .healthCheckFailed
                }
                
                // Check protocol version compatibility
                if let health = result.healthResponse {
                    guard health.protocolVersion >= ConnectionProfile.minimumProtocolVersion else {
                        throw ConnectionError.backendVersionMismatch(
                            backend: health.version,
                            minRequired: "\(ConnectionProfile.minimumProtocolVersion)"
                        )
                    }
                }
                
                // Establish WebSocket connection
                try await establishWebSocket(profile)
                
                // Update state
                activeProfile = profile
                state = .connected(profile)
                feedMode = .websocket
                
                // Update metrics
                try? await store.updateConnectionMetrics(id: profile.id, latencyMs: result.latencyMs)
                
                // Success - return
                return
                
            } catch let error as ConnectionError {
                lastError = error
                
                // Don't retry on auth failures
                if case .authenticationFailed = error {
                    state = .failed(error)
                    feedMode = .offline
                    return
                }
                
                // If we have more retries, wait before trying again
                if attempt < maxRetries {
                    let delay = min(pow(2.0, Double(attempt)), 5.0)  // Max 5s between retries
                    try? await Task.sleep(for: .seconds(delay))
                }
            } catch {
                lastError = .healthCheckFailed
            }
        }
        
        // All retries exhausted
        state = .failed(lastError ?? .healthCheckFailed)
        feedMode = .offline
    }
    
    /// Connect with automatic fallback through all available profiles
    func connectWithFallback() async {
        await loadProfiles()
        
        let ordered = prioritize(availableProfiles)
        
        for (index, profile) in ordered.enumerated() {
            // Check for cancellation
            guard !Task.isCancelled else { return }
            
            // Only retry the first (default) profile
            let retries = index == 0 ? 2 : 0
            await connect(to: profile, maxRetries: retries)
            
            if case .connected = state {
                return
            }
        }
        
        state = .failed(.allProfilesFailed)
    }
    
    /// Connect to the fastest responding profile
    func connectToFastest(timeout: TimeInterval = 10) async {
        await loadProfiles()
        
        guard !availableProfiles.isEmpty else {
            state = .failed(.allProfilesFailed)
            return
        }
        
        // Create a timeout task
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
        }
        
        // Probe all profiles in parallel with limited concurrency
        let results = await withTaskGroup(of: ProbeResult.self) { group in
            var submitted = 0
            
            for profile in availableProfiles {
                // Limit concurrent probes
                while submitted >= self.maxConcurrentProbes {
                    if let result = await group.next() {
                        submitted -= 1
                        self.setProbeResult(result)
                    }
                }
                
                // Check for timeout or cancellation
                if timeoutTask.isCancelled || Task.isCancelled {
                    group.cancelAll()
                    break
                }
                
                group.addTask {
                    await self.probe(profile)
                }
                submitted += 1
            }
            
            // Collect remaining results
            var results: [ProbeResult] = []
            for await result in group {
                self.setProbeResult(result)
                results.append(result)
            }
            return results
        }
        
        timeoutTask.cancel()
        
        // Find successful results and sort by latency
        let successful = results
            .filter { $0.success }
            .sorted { $0.latencyMs < $1.latencyMs }
        
        // Connect to fastest, or fall back to priority order
        if let fastest = successful.first {
            await connect(to: fastest.profile)
        } else {
            await connectWithFallback()
        }
    }
    
    /// Disconnect from current backend
    func disconnect() {
        reconnectTask?.cancel()
        webSocket?.disconnect()
        activeProfile = nil
        state = .disconnected
        feedMode = .offline
    }
    
    /// Reconnect to the same profile
    func reconnect() async {
        guard let profile = activeProfile else {
            await connectWithFallback()
            return
        }
        await connect(to: profile, maxRetries: 3)
    }
    
    /// Get the last probe result for a profile
    func probeResult(for profileID: UUID) -> ProbeResult? {
        probeResultsLock.lock()
        defer { probeResultsLock.unlock() }
        return probeResults[profileID]
    }
    
    // MARK: - Probing
    
    /// Probe a profile to check connectivity and measure latency
    /// - Parameter profile: The profile to probe
    /// - Returns: ProbeResult with success status, latency, and health response
    func probe(_ profile: ConnectionProfile) async -> ProbeResult {
        // Validate profile first
        do {
            try profile.validate()
        } catch let error as ConnectionProfile.ValidationError {
            return .failure(profile: profile, error: .discoveryFailed(error.localizedDescription ?? "Invalid profile"))
        } catch {
            return .failure(profile: profile, error: .discoveryFailed("Profile validation failed"))
        }
        
        guard let url = profile.healthURL else {
            return .failure(profile: profile, error: .invalidURL)
        }
        
        var request = URLRequest(
            url: url,
            timeoutInterval: profile.kind.probeTimeout
        )
        
        // Apply auth if needed
        if case .bearerToken = profile.authMethod {
            let token = await store.resolveToken("keychain-ref", for: profile.id)
            profile.authMethod.apply(to: &request) { _ in token }
        }
        
        let start = ContinuousClock().now
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int((ContinuousClock().now - start).components.attoseconds / 1_000_000_000_000_000)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(profile: profile, error: .healthCheckFailed)
            }
            
            switch httpResponse.statusCode {
            case 200:
                // Parse health response
                let healthResponse = try? JSONDecoder().decode(HealthResponse.self, from: data)
                return .success(profile: profile, latencyMs: max(latencyMs, 1), healthResponse: healthResponse)
                
            case 401:
                return .failure(profile: profile, error: .authenticationFailed)
                
            default:
                return .failure(profile: profile, error: .healthCheckFailed)
            }
            
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .failure(profile: profile, error: .healthCheckTimeout)
            case .notConnectedToInternet:
                return .failure(profile: profile, error: .networkUnavailable)
            case .cannotConnectToHost:
                return .failure(profile: profile, error: .healthCheckFailed)
            case .dnsLookupFailed:
                return .failure(profile: profile, error: .discoveryFailed("DNS lookup failed"))
            default:
                return .failure(profile: profile, error: .healthCheckFailed)
            }
        } catch {
            return .failure(profile: profile, error: .healthCheckFailed)
        }
    }
    
    /// Probe all profiles and update results
    /// - Returns: Array of probe results for all profiles
    func probeAll() async -> [ProbeResult] {
        await loadProfiles()
        
        let results = await withTaskGroup(of: ProbeResult.self) { group in
            for profile in availableProfiles {
                group.addTask {
                    await self.probe(profile)
                }
            }
            
            var results: [ProbeResult] = []
            for await result in group {
                self.setProbeResult(result)
                results.append(result)
            }
            return results
        }
        
        return results
    }
    
    // MARK: - Private
    
    private func setProbeResult(_ result: ProbeResult) {
        probeResultsLock.lock()
        probeResults[result.profile.id] = result
        probeResultsLock.unlock()
    }
    
    private func establishWebSocket(_ profile: ConnectionProfile) async throws {
        guard let ws = webSocket else {
            // No WebSocket instance provided, HTTP-only mode
            return
        }
        
        // Configure WebSocket with profile
        ws.host = profile.backendHost
        ws.port = profile.backendPort
        
        // Connect with token if needed
        let token = await store.resolveToken("keychain-ref", for: profile.id)
        
        // The actual WebSocket connection happens via the BridgeWebSocket class
        if let token = token {
            ws.connect(profile: profile, role: .human, name: "macos-ui", token: token)
        } else {
            ws.connect(role: .human, name: "macos-ui")
        }
        
        // Wait for connection with timeout and cancellation checks
        let connectionTimeout: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds
        let startTime = ContinuousClock().now
        
        while !ws.isConnected {
            // Check for cancellation
            if Task.isCancelled {
                throw ConnectionError.webSocketUpgradeFailed
            }
            
            // Check for timeout
            let elapsed = ContinuousClock().now - startTime
            if elapsed.components.attoseconds > connectionTimeout * 1_000_000_000 {
                throw ConnectionError.webSocketUpgradeFailed
            }
            
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    
    private func prioritize(_ profiles: [ConnectionProfile]) -> [ConnectionProfile] {
        profiles.sorted { a, b in
            // 1. Default profile first
            if a.isDefault != b.isDefault { return a.isDefault }
            // 2. Then by kind priority: local → tailscale → custom
            if a.kind != b.kind { return a.kind.priority < b.kind.priority }
            // 3. Then by most recently connected
            return (a.lastConnected ?? .distantPast) > (b.lastConnected ?? .distantPast)
        }
    }
    
    /// Start automatic reconnection with exponential backoff
    private func startReconnect(profile: ConnectionProfile, attempt: Int = 1) {
        guard attempt <= maxReconnectAttempts else {
            state = .failed(.allProfilesFailed)
            return
        }
        
        state = .reconnecting(lastProfile: profile, attempt: attempt)
        
        let delay = min(pow(2.0, Double(attempt - 1)), 30.0)  // Max 30s
        
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                // Task was cancelled
                return
            }
            
            guard let self = self, !Task.isCancelled else { return }
            
            await self.connect(to: profile)
            
            if case .connected = self.state {
                // Reconnected successfully
                return
            } else {
                // Try again
                self.startReconnect(profile: profile, attempt: attempt + 1)
            }
        }
    }
}
