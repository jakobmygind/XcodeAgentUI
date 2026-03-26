import Foundation

/// Errors that can occur during connection operations
enum ConnectionError: LocalizedError, Sendable, Equatable {
    case healthCheckFailed
    case healthCheckTimeout
    case webSocketUpgradeFailed
    case authenticationFailed
    case allProfilesFailed
    case backendVersionMismatch(backend: String, minRequired: String)
    case tailscaleNotRunning
    case invalidURL
    case networkUnavailable
    case discoveryFailed(String)
    case profileNotFound(UUID)
    case duplicateProfileId(UUID)
    case keychainError(String)
    case invalidProfile(String)
    
    var errorDescription: String? {
        switch self {
        case .healthCheckFailed:
            return "Backend is not responding. Check that the agent service is running."
        case .healthCheckTimeout:
            return "Connection timed out. The backend may be on a different network."
        case .webSocketUpgradeFailed:
            return "Connected to backend but real-time feed failed. Falling back to polling."
        case .authenticationFailed:
            return "Authentication failed. Check your API token in profile settings."
        case .allProfilesFailed:
            return "Could not connect to any configured backend."
        case .backendVersionMismatch(let v, let min):
            return "Backend version \(v) is too old. Minimum required: \(min)."
        case .tailscaleNotRunning:
            return "Tailscale is not running. Start Tailscale to connect to remote backends."
        case .invalidURL:
            return "Invalid URL configuration."
        case .networkUnavailable:
            return "Network is unavailable."
        case .discoveryFailed(let reason):
            return "Discovery failed: \(reason)"
        case .profileNotFound:
            return "Connection profile not found."
        case .duplicateProfileId:
            return "A profile with this ID already exists."
        case .keychainError(let reason):
            return "Keychain error: \(reason)"
        case .invalidProfile(let reason):
            return "Invalid profile: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .healthCheckFailed:
            return "Ensure the backend is running and the port is correct."
        case .healthCheckTimeout:
            return "Check your network connection and try again."
        case .webSocketUpgradeFailed:
            return "The HTTP API may work, but real-time updates are unavailable."
        case .authenticationFailed:
            return "Verify your bearer token in profile settings."
        case .allProfilesFailed:
            return "Check that at least one backend is running and accessible."
        case .backendVersionMismatch:
            return "Update the backend to the latest version."
        case .tailscaleNotRunning:
            return "Start the Tailscale app and ensure you're logged in."
        case .invalidURL:
            return "Check the host and port settings in your profile."
        case .networkUnavailable:
            return "Check your Wi-Fi or network connection."
        case .discoveryFailed:
            return "Try manual profile configuration instead."
        case .profileNotFound:
            return "Create a new connection profile."
        case .duplicateProfileId:
            return "Try again with a different profile."
        case .keychainError:
            return "Check Keychain access permissions."
        case .invalidProfile(let reason):
            return "Fix profile configuration: \(reason)"
        }
    }
    
    /// Compare two errors for equality based on their type and key properties
    func isEqual(to other: ConnectionError) -> Bool {
        switch (self, other) {
        case (.healthCheckFailed, .healthCheckFailed):
            return true
        case (.healthCheckTimeout, .healthCheckTimeout):
            return true
        case (.webSocketUpgradeFailed, .webSocketUpgradeFailed):
            return true
        case (.authenticationFailed, .authenticationFailed):
            return true
        case (.allProfilesFailed, .allProfilesFailed):
            return true
        case (.backendVersionMismatch(let v1, let m1), .backendVersionMismatch(let v2, let m2)):
            return v1 == v2 && m1 == m2
        case (.tailscaleNotRunning, .tailscaleNotRunning):
            return true
        case (.invalidURL, .invalidURL):
            return true
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.discoveryFailed(let r1), .discoveryFailed(let r2)):
            return r1 == r2
        case (.profileNotFound(let id1), .profileNotFound(let id2)):
            return id1 == id2
        case (.duplicateProfileId(let id1), .duplicateProfileId(let id2)):
            return id1 == id2
        case (.keychainError(let r1), .keychainError(let r2)):
            return r1 == r2
        case (.invalidProfile(let r1), .invalidProfile(let r2)):
            return r1 == r2
        default:
            return false
        }
    }
}

/// Health check response from backend
struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let protocolVersion: Int
    let timestamp: String
    
    var isOK: Bool {
        status == "ok"
    }
    
    var date: Date? {
        ISO8601DateFormatter().date(from: timestamp)
    }
}

/// Connection state for UI representation
enum ConnectionState: Sendable, Equatable {
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
        case (.reconnecting(let a1, let a2), .reconnecting(let b1, let b2)):
            return a1.id == b1.id && a2 == b2
        case (.failed(let a), .failed(let b)):
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
        if case .connecting = self { return true }
        if case .reconnecting = self { return true }
        return false
    }
    
    var activeProfile: ConnectionProfile? {
        switch self {
        case .connected(let profile):
            return profile
        case .reconnecting(let profile, _):
            return profile
        default:
            return nil
        }
    }
    
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting(let kind):
            return "Connecting to \(kind.displayName)..."
        case .connected(let profile):
            return profile.name
        case .reconnecting(let profile, let attempt):
            return "Reconnecting to \(profile.name) (attempt \(attempt))"
        case .failed(let error):
            return error.localizedDescription
        }
    }
}

/// Feed mode for real-time updates
enum FeedMode: Equatable, Sendable {
    case websocket       // real-time push — ideal
    case polling(Int)    // HTTP polling interval in seconds — fallback
    case offline         // no connection — show last known state
}

/// Result of a latency probe
struct ProbeResult: Sendable {
    let profile: ConnectionProfile
    let latencyMs: Int
    let timestamp: Date
    let success: Bool
    let error: ConnectionError?
    let healthResponse: HealthResponse?
    
    init(
        profile: ConnectionProfile,
        latencyMs: Int,
        timestamp: Date = Date(),
        success: Bool,
        error: ConnectionError? = nil,
        healthResponse: HealthResponse? = nil
    ) {
        self.profile = profile
        self.latencyMs = latencyMs
        self.timestamp = timestamp
        self.success = success
        self.error = error
        self.healthResponse = healthResponse
    }
    
    static func success(
        profile: ConnectionProfile,
        latencyMs: Int,
        healthResponse: HealthResponse? = nil
    ) -> ProbeResult {
        ProbeResult(
            profile: profile,
            latencyMs: latencyMs,
            timestamp: Date(),
            success: true,
            error: nil,
            healthResponse: healthResponse
        )
    }
    
    static func failure(profile: ConnectionProfile, error: ConnectionError) -> ProbeResult {
        ProbeResult(
            profile: profile,
            latencyMs: -1,
            timestamp: Date(),
            success: false,
            error: error,
            healthResponse: nil
        )
    }
}

/// Errors that can occur during profile storage operations
enum ProfileStoreError: LocalizedError, Sendable {
    case fileReadError(URL, String)
    case fileWriteError(URL, String)
    case decodingError(String)
    case encodingError(String)
    case directoryCreationFailed(URL, String)
    
    var errorDescription: String? {
        switch self {
        case .fileReadError(let url, let details):
            return "Failed to read profiles from \(url.path): \(details)"
        case .fileWriteError(let url, let details):
            return "Failed to write profiles to \(url.path): \(details)"
        case .decodingError(let details):
            return "Failed to decode profiles: \(details)"
        case .encodingError(let details):
            return "Failed to encode profiles: \(details)"
        case .directoryCreationFailed(let url, let details):
            return "Failed to create directory at \(url.path): \(details)"
        }
    }
}
