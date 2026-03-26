import Foundation

/// Errors that can occur during connection operations
enum ConnectionError: LocalizedError, Sendable {
    case healthCheckFailed(URL, Int)
    case healthCheckTimeout(URL, TimeInterval)
    case webSocketUpgradeFailed(URL, String)
    case authenticationFailed(URL)
    case allProfilesFailed
    case backendVersionMismatch(backend: String, required: Int)
    case tailscaleNotRunning
    case invalidProfile(ConnectionProfile)
    case keychainError(String)
    case profileNotFound(UUID)
    case noDefaultProfile
    case networkUnavailable
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .healthCheckFailed(let url, let status):
            return "Backend at \(url.host ?? "unknown") returned status \(status). Check that the agent service is running."
            
        case .healthCheckTimeout(let url, let timeout):
            return "Connection to \(url.host ?? "unknown") timed out after \(String(format: "%.1f", timeout))s. The backend may be on a different network."
            
        case .webSocketUpgradeFailed(let url, let reason):
            return "Connected to \(url.host ?? "unknown") but real-time feed failed: \(reason). Falling back to polling."
            
        case .authenticationFailed(let url):
            return "Authentication failed for \(url.host ?? "unknown"). Check your API token in profile settings."
            
        case .allProfilesFailed:
            return "Could not connect to any configured backend."
            
        case .backendVersionMismatch(let version, let required):
            return "Backend version \(version) is incompatible. Minimum protocol version required: \(required)."
            
        case .tailscaleNotRunning:
            return "Tailscale is not running. Start Tailscale to connect to remote backends."
            
        case .invalidProfile(let profile):
            return "Profile '\(profile.name)' is not fully configured (host: '\(profile.backendHost)')."
            
        case .keychainError(let details):
            return "Keychain error: \(details)"
            
        case .profileNotFound(let id):
            return "Profile with ID \(id) not found."
            
        case .noDefaultProfile:
            return "No default profile is set. Please select a profile to connect."
            
        case .networkUnavailable:
            return "Network is unavailable. Check your connection and try again."
            
        case .decodingError(let details):
            return "Failed to parse response: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .healthCheckFailed:
            return "Ensure the OpenClaw backend is running on the target machine."
        case .healthCheckTimeout:
            return "Check that the host is reachable and the correct port is open."
        case .webSocketUpgradeFailed:
            return "The backend may be overloaded. Try reconnecting."
        case .authenticationFailed:
            return "Verify your bearer token in Profile Settings."
        case .allProfilesFailed:
            return "Check your network connection and backend status."
        case .backendVersionMismatch:
            return "Update the OpenClaw backend to the latest version."
        case .tailscaleNotRunning:
            return "Launch the Tailscale app and ensure you're logged in."
        case .invalidProfile:
            return "Edit the profile and provide a valid hostname or IP address."
        case .keychainError:
            return "Try resetting the profile's authentication token."
        case .profileNotFound:
            return "The profile may have been deleted. Create a new one."
        case .noDefaultProfile:
            return "Open the connection switcher and select a profile as default."
        case .networkUnavailable:
            return "Check your Wi-Fi or Ethernet connection."
        case .decodingError:
            return "The backend may be returning unexpected data."
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .healthCheckFailed, .healthCheckTimeout, .webSocketUpgradeFailed,
             .networkUnavailable:
            return true
        case .authenticationFailed, .backendVersionMismatch, .invalidProfile,
             .keychainError, .profileNotFound, .noDefaultProfile, .allProfilesFailed,
             .tailscaleNotRunning, .decodingError:
            return false
        }
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

/// Errors that can occur during discovery operations
enum DiscoveryError: LocalizedError, Sendable {
    case bonjourNotAvailable
    case tailscaleAPINotAvailable
    case invalidPeerData(String)
    case probeFailed(URL, String)
    
    var errorDescription: String? {
        switch self {
        case .bonjourNotAvailable:
            return "Bonjour/mDNS discovery is not available on this network."
        case .tailscaleAPINotAvailable:
            return "Tailscale local API is not responding. Is Tailscale running?"
        case .invalidPeerData(let details):
            return "Received invalid peer data: \(details)"
        case .probeFailed(let url, let reason):
            return "Failed to probe \(url.host ?? "unknown"): \(reason)"
        }
    }
}
