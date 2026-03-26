import Foundation

/// Represents a connection configuration to an OpenClaw backend
struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var kind: ProfileKind
    var backendHost: String
    var backendPort: Int
    var useTLS: Bool
    var authMethod: AuthMethod
    var isDefault: Bool
    var lastConnected: Date?
    var lastLatencyMs: Int?
    
    /// Validation errors for connection profiles
    enum ValidationError: LocalizedError, Sendable {
        case emptyName
        case emptyHost
        case invalidPort(Int)
        case invalidHost(String)
        
        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "Profile name cannot be empty"
            case .emptyHost:
                return "Backend host cannot be empty"
            case .invalidPort(let port):
                return "Invalid port number: \(port). Must be between 1 and 65535."
            case .invalidHost(let host):
                return "Invalid host: '\(host)'. Host cannot contain spaces or special characters."
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        kind: ProfileKind,
        backendHost: String,
        backendPort: Int,
        useTLS: Bool = false,
        authMethod: AuthMethod = .none,
        isDefault: Bool = false,
        lastConnected: Date? = nil,
        lastLatencyMs: Int? = nil
    ) throws {
        // Validate inputs
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ValidationError.emptyName
        }
        
        let trimmedHost = backendHost.trimmingCharacters(in: .whitespacesAndNewlines)
        // Host can be empty for unconfigured profiles (like default Tailscale)
        if !trimmedHost.isEmpty {
            guard Self.isValidHost(trimmedHost) else {
                throw ValidationError.invalidHost(trimmedHost)
            }
        }
        
        guard backendPort > 0 && backendPort <= 65535 else {
            throw ValidationError.invalidPort(backendPort)
        }
        
        self.id = id
        self.name = trimmedName
        self.kind = kind
        self.backendHost = trimmedHost
        self.backendPort = backendPort
        self.useTLS = useTLS
        self.authMethod = authMethod
        self.isDefault = isDefault
        self.lastConnected = lastConnected
        self.lastLatencyMs = lastLatencyMs
    }
    
    /// Validates a host string
    private static func isValidHost(_ host: String) -> Bool {
        // Allow localhost, IP addresses, and hostnames
        // Reject strings with spaces or obviously invalid characters
        let invalidCharacters = CharacterSet(charactersIn: " /\\?#[]@!$&'()*+,;=")
        return host.rangeOfCharacter(from: invalidCharacters) == nil
    }
    
    /// HTTP base URL for this profile
    var baseURL: URL? {
        let scheme = useTLS ? "https" : "http"
        let urlString = "\(scheme)://\(backendHost):\(backendPort)"
        return URL(string: urlString)
    }
    
    /// WebSocket URL for this profile
    var wsURL: URL? {
        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(backendHost):\(backendPort)"
        return URL(string: urlString)
    }
    
    /// Health check endpoint URL
    var healthURL: URL? {
        guard let base = baseURL else { return nil }
        return base.appendingPathComponent("/api/health")
    }
    
    /// Returns true if this profile is configured (has a valid host)
    var isConfigured: Bool {
        !backendHost.isEmpty && backendPort > 0 && backendPort <= 65535
    }
    
    /// Human-readable description of the connection endpoint
    var endpointDescription: String {
        "\(backendHost):\(backendPort)"
    }
    
    /// Validates the profile and returns any validation errors
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errors.append(.emptyName)
        }
        
        let trimmedHost = backendHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty && !Self.isValidHost(trimmedHost) {
            errors.append(.invalidHost(trimmedHost))
        }
        
        if backendPort <= 0 || backendPort > 65535 {
            errors.append(.invalidPort(backendPort))
        }
        
        return errors
    }
}

/// The type of connection profile
enum ProfileKind: String, Codable, CaseIterable, Sendable {
    case local       // localhost — same machine
    case tailscale   // Tailscale IP or MagicDNS hostname
    case custom      // manual host:port (VPN, SSH tunnel, etc.)
    
    var displayName: String {
        switch self {
        case .local: return "Local"
        case .tailscale: return "Tailscale"
        case .custom: return "Custom"
        }
    }
    
    var icon: String {
        switch self {
        case .local: return "desktopcomputer"
        case .tailscale: return "network"
        case .custom: return "externaldrive.connected.to.line.below"
        }
    }
    
    var color: String {
        switch self {
        case .local: return "green"
        case .tailscale: return "blue"
        case .custom: return "orange"
        }
    }
    
    /// Priority for fallback ordering (lower = tried first)
    var priority: Int {
        switch self {
        case .local: return 0
        case .tailscale: return 1
        case .custom: return 2
        }
    }
}

/// Authentication method for a connection profile
enum AuthMethod: Codable, Sendable, Hashable {
    case none                        // local only — no auth needed
    case bearerToken(keychainRef: String)  // reference to Keychain entry
    
    enum CodingKeys: String, CodingKey {
        case type, keychainRef
    }
    
    enum AuthType: String, Codable, Sendable {
        case none, bearerToken
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(AuthType.none, forKey: .type)
        case .bearerToken(let ref):
            try container.encode(AuthType.bearerToken, forKey: .type)
            try container.encode(ref, forKey: .keychainRef)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AuthType.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .bearerToken:
            let ref = try container.decode(String.self, forKey: .keychainRef)
            self = .bearerToken(keychainRef: ref)
        }
    }
    
    static func == (lhs: AuthMethod, rhs: AuthMethod) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.bearerToken(let a), .bearerToken(let b)):
            return a == b
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .none:
            hasher.combine(0)
        case .bearerToken(let ref):
            hasher.combine(1)
            hasher.combine(ref)
        }
    }
}

// MARK: - Default Profiles

extension ConnectionProfile {
    /// Default local profile (localhost:9300 for WebSocket)
    static func localDefault() -> ConnectionProfile {
        // Use try! here because we know these values are valid
        // This is acceptable for hardcoded defaults that are tested
        try! ConnectionProfile(
            id: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440001")!,
            name: "Local",
            kind: .local,
            backendHost: "localhost",
            backendPort: 9300,
            useTLS: false,
            authMethod: .none,
            isDefault: true
        )
    }
    
    /// Default Tailscale profile (empty, needs configuration)
    static func tailscaleDefault() -> ConnectionProfile {
        try! ConnectionProfile(
            id: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440002")!,
            name: "Tailscale",
            kind: .tailscale,
            backendHost: "",
            backendPort: 9300,
            useTLS: false,
            authMethod: .bearerToken(keychainRef: "550E8400-E29B-41D4-A716-446655440002"),
            isDefault: false
        )
    }
}
