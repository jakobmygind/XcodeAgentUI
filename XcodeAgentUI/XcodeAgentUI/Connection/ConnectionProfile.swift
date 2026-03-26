import Foundation

/// Represents a connection profile for connecting to an OpenClaw backend
struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    /// Minimum supported protocol version for compatibility
    static let minimumProtocolVersion = 1
    
    /// Default ports for different services
    static let defaultWebSocketPort = 9300
    static let defaultHTTPPort = 3800
    
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
    
    /// Validation errors for profile configuration
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
                return "Host cannot be empty"
            case .invalidPort(let port):
                return "Port \(port) is invalid. Must be 1-65535"
            case .invalidHost(let host):
                return "Host '\(host)' contains invalid characters"
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
    ) throws(ValidationError) {
        // Validate and trim inputs
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = backendHost.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            throw .emptyName
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
    
    /// Validates the profile configuration
    func validate() throws(ValidationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyName
        }
        
        guard !backendHost.isEmpty else {
            throw .emptyHost
        }
        
        guard backendPort > 0 && backendPort <= 65535 else {
            throw .invalidPort(backendPort)
        }
        
        // Check for invalid characters in host
        let invalidCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let hostSet = CharacterSet(charactersIn: backendHost)
        if !hostSet.isSubset(of: invalidCharacters) {
            throw .invalidHost(backendHost)
        }
    }
    
    /// HTTP base URL for this profile
    /// - Returns: URL if valid, nil otherwise
    var baseURL: URL? {
        let scheme = useTLS ? "https" : "http"
        let urlString = "\(scheme)://\(backendHost):\(backendPort)"
        return URL(string: urlString)
    }
    
    /// WebSocket URL for this profile
    /// - Returns: URL if valid, nil otherwise
    var wsURL: URL? {
        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(backendHost):\(backendPort)"
        return URL(string: urlString)
    }
    
    /// Health check endpoint URL
    /// - Returns: URL if valid, nil otherwise
    var healthURL: URL? {
        guard let base = baseURL else { return nil }
        return base
            .appendingPathComponent("api")
            .appendingPathComponent("health")
    }
    
    /// WebSocket URL with query parameters for connection
    /// - Parameters:
    ///   - role: Client role (agent, human, observer)
    ///   - name: Client name identifier
    ///   - token: Optional authentication token
    /// - Returns: URL if valid, nil otherwise
    func wsURL(role: ClientRole = .observer, name: String = "macos-ui", token: String? = nil) -> URL? {
        guard var components = URLComponents(url: wsURL ?? URL(string: "ws://localhost:9300")!, resolvingAgainstBaseURL: true) else {
            return nil
        }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "role", value: role.rawValue),
            URLQueryItem(name: "name", value: name)
        ]
        
        if let token = token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        
        components.queryItems = queryItems
        return components.url
    }
    
    /// Returns a validated copy of this profile or throws
    func validated() throws(ValidationError) -> ConnectionProfile {
        try validate()
        return self
    }
    
    /// Returns true if this profile is configured (has a valid host)
    var isConfigured: Bool {
        !backendHost.isEmpty && backendPort > 0 && backendPort <= 65535
    }
    
    /// Human-readable description of the connection endpoint
    var endpointDescription: String {
        "\(backendHost):\(backendPort)"
    }
}

enum ProfileKind: String, Codable, Sendable, CaseIterable {
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
    
    var priority: Int {
        switch self {
        case .local: return 0
        case .tailscale: return 1
        case .custom: return 2
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
    
    /// Default timeout for this profile kind
    var probeTimeout: TimeInterval {
        switch self {
        case .local:
            return 1.0  // Local should respond in <10ms
        case .tailscale:
            return 5.0  // WireGuard handshake can take 2-3s
        case .custom:
            return 5.0  // Unknown network conditions
        }
    }
}

enum AuthMethod: Codable, Sendable, Hashable {
    case none                        // local only — no auth needed
    case bearerToken(String)         // pre-shared API key (stored reference, actual token in Keychain)
    
    enum CodingKeys: String, CodingKey {
        case type, token
    }
    
    enum AuthType: String, Codable, Sendable {
        case none, bearerToken
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(AuthType.none, forKey: .type)
        case .bearerToken(let token):
            try container.encode(AuthType.bearerToken, forKey: .type)
            try container.encode(token, forKey: .token)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AuthType.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .bearerToken:
            let token = try container.decode(String.self, forKey: .token)
            self = .bearerToken(token)
        }
    }
    
    /// Apply auth to a URLRequest
    /// - Parameters:
    ///   - request: The URLRequest to modify
    ///   - tokenResolver: Closure to resolve token references to actual tokens
    func apply(to request: inout URLRequest, tokenResolver: (String) -> String? = { _ in nil }) {
        switch self {
        case .none:
            break
        case .bearerToken(let tokenRef):
            // tokenRef is either the actual token or a keychain reference
            let token = tokenResolver(tokenRef) ?? tokenRef
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    /// Get WebSocket URL with auth token as query parameter
    /// - Parameters:
    ///   - url: Base WebSocket URL
    ///   - tokenResolver: Closure to resolve token references
    /// - Returns: URL with auth token appended if applicable
    func applyToWebSocket(_ url: URL, tokenResolver: (String) -> String? = { _ in nil }) -> URL {
        switch self {
        case .none:
            return url
        case .bearerToken(let tokenRef):
            let token = tokenResolver(tokenRef) ?? tokenRef
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                return url
            }
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "token", value: token))
            components.queryItems = queryItems
            return components.url ?? url
        }
    }
}

// MARK: - Built-in Profiles

extension ConnectionProfile {
    /// Default local profile
    static var local: ConnectionProfile {
        try! ConnectionProfile(
            name: "Local",
            kind: .local,
            backendHost: "localhost",
            backendPort: defaultWebSocketPort,
            useTLS: false,
            authMethod: .none,
            isDefault: true
        )
    }
    
    /// Template for Tailscale profile (host to be filled in)
    static func tailscale(host: String, port: Int = defaultWebSocketPort) -> ConnectionProfile {
        try! ConnectionProfile(
            name: "Tailscale (\(host))",
            kind: .tailscale,
            backendHost: host,
            backendPort: port,
            useTLS: false,
            authMethod: .bearerToken("keychain-ref"),
            isDefault: false
        )
    }
}
