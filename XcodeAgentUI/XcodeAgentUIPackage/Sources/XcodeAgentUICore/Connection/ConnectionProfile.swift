import Foundation

/// Represents a connection profile for connecting to an OpenClaw backend
public struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    // Custom Equatable: profiles are equal if they have the same ID
    public static func == (lhs: ConnectionProfile, rhs: ConnectionProfile) -> Bool {
        lhs.id == rhs.id
    }

    // Custom Hashable: hash based on ID only
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case backendHost
        case backendPort
        case httpPort
        case webSocketPort
        case useTLS
        case authMethod
        case isDefault
        case lastConnected
        case lastLatencyMs
    }

    /// Minimum supported protocol version for compatibility
    public static let minimumProtocolVersion = 1
    
    /// Default ports for different services
    public static let defaultWebSocketPort = 9300
    public static let defaultHTTPPort = 3800
    
    public let id: UUID
    public var name: String
    public var kind: ProfileKind
    public var backendHost: String
    /// Legacy compatibility alias for the bridge/WebSocket port.
    public var backendPort: Int {
        get { webSocketPort }
        set { webSocketPort = newValue }
    }
    public var httpPort: Int
    public var webSocketPort: Int
    public var useTLS: Bool
    public var authMethod: AuthMethod
    public var isDefault: Bool
    public var lastConnected: Date?
    public var lastLatencyMs: Int?
    
    /// Validation errors for profile configuration
    public enum ValidationError: LocalizedError, Sendable {
        case emptyName
        case emptyHost
        case invalidPort(Int)
        case invalidHost(String)
        
        public var errorDescription: String? {
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
    
    public init(
        id: UUID = UUID(),
        name: String,
        kind: ProfileKind,
        backendHost: String,
        backendPort: Int,
        httpPort: Int? = nil,
        webSocketPort: Int? = nil,
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

        let resolvedWebSocketPort = webSocketPort ?? backendPort
        let resolvedHTTPPort = httpPort ?? backendPort

        // Validate port range
        guard resolvedWebSocketPort > 0 && resolvedWebSocketPort <= 65535 else {
            throw .invalidPort(resolvedWebSocketPort)
        }

        guard resolvedHTTPPort > 0 && resolvedHTTPPort <= 65535 else {
            throw .invalidPort(resolvedHTTPPort)
        }

        // Validate host characters (if host is provided)
        if !trimmedHost.isEmpty {
            let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
            let hostSet = CharacterSet(charactersIn: trimmedHost)
            if !hostSet.isSubset(of: allowedCharacters) {
                throw .invalidHost(trimmedHost)
            }
        }

        self.id = id
        self.name = trimmedName
        self.kind = kind
        self.backendHost = trimmedHost
        self.httpPort = resolvedHTTPPort
        self.webSocketPort = resolvedWebSocketPort
        self.useTLS = useTLS
        self.authMethod = authMethod
        self.isDefault = isDefault
        self.lastConnected = lastConnected
        self.lastLatencyMs = lastLatencyMs
    }
    
    /// Validates the profile configuration
    public func validate() throws(ValidationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyName
        }
        
        guard !backendHost.isEmpty else {
            throw .emptyHost
        }
        
        guard webSocketPort > 0 && webSocketPort <= 65535 else {
            throw .invalidPort(webSocketPort)
        }

        guard httpPort > 0 && httpPort <= 65535 else {
            throw .invalidPort(httpPort)
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
    public var baseURL: URL? {
        guard !backendHost.isEmpty else { return nil }
        let scheme = useTLS ? "https" : "http"
        let urlString = "\(scheme)://\(backendHost):\(httpPort)"
        return URL(string: urlString)
    }

    /// WebSocket URL for this profile
    /// - Returns: URL if valid, nil otherwise
    public var wsURL: URL? {
        guard !backendHost.isEmpty else { return nil }
        let scheme = useTLS ? "wss" : "ws"
        let urlString = "\(scheme)://\(backendHost):\(webSocketPort)"
        return URL(string: urlString)
    }

    /// Health check endpoint URL
    /// - Returns: URL if valid, nil otherwise
    public var healthURL: URL? {
        guard !backendHost.isEmpty else { return nil }
        guard let base = baseURL else { return nil }
        return base.appendingPathComponent("health")
    }
    
    /// WebSocket URL with query parameters for connection
    /// - Parameters:
    ///   - role: Client role (agent, human, observer)
    ///   - name: Client name identifier
    ///   - token: Optional authentication token
    /// - Returns: URL if valid, nil otherwise
    public func wsURL(role: ClientRole = .observer, name: String = "macos-ui", token: String? = nil) -> URL? {
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
    public func validated() throws(ValidationError) -> ConnectionProfile {
        try validate()
        return self
    }
    
    /// Returns true if this profile is configured (has a valid host)
    public var isConfigured: Bool {
        !backendHost.isEmpty && httpPort > 0 && httpPort <= 65535 && webSocketPort > 0 && webSocketPort <= 65535
    }
    
    /// Human-readable description of the connection endpoint
    public var endpointDescription: String {
        "\(backendHost) · http:\(httpPort) / ws:\(webSocketPort)"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let name = try container.decode(String.self, forKey: .name)
        let kind = try container.decode(ProfileKind.self, forKey: .kind)
        let backendHost = try container.decode(String.self, forKey: .backendHost)
        let legacyPort = try container.decodeIfPresent(Int.self, forKey: .backendPort)
        let httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort)
        let webSocketPort = try container.decodeIfPresent(Int.self, forKey: .webSocketPort)
        let useTLS = try container.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
        let authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .none
        let isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        let lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        let lastLatencyMs = try container.decodeIfPresent(Int.self, forKey: .lastLatencyMs)

        try self.init(
            id: id,
            name: name,
            kind: kind,
            backendHost: backendHost,
            backendPort: legacyPort ?? webSocketPort ?? ConnectionProfile.defaultWebSocketPort,
            httpPort: httpPort,
            webSocketPort: webSocketPort,
            useTLS: useTLS,
            authMethod: authMethod,
            isDefault: isDefault,
            lastConnected: lastConnected,
            lastLatencyMs: lastLatencyMs
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(backendHost, forKey: .backendHost)
        try container.encode(httpPort, forKey: .httpPort)
        try container.encode(webSocketPort, forKey: .webSocketPort)
        try container.encode(webSocketPort, forKey: .backendPort)
        try container.encode(useTLS, forKey: .useTLS)
        try container.encode(authMethod, forKey: .authMethod)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encodeIfPresent(lastConnected, forKey: .lastConnected)
        try container.encodeIfPresent(lastLatencyMs, forKey: .lastLatencyMs)
    }
}

public enum ProfileKind: String, Codable, Sendable, CaseIterable {
    case local       // localhost — same machine
    case tailscale   // Tailscale IP or MagicDNS hostname
    case custom      // manual host:port (VPN, SSH tunnel, etc.)
    
    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .tailscale: return "Tailscale"
        case .custom: return "Custom"
        }
    }
    
    public var priority: Int {
        switch self {
        case .local: return 0
        case .tailscale: return 1
        case .custom: return 2
        }
    }
    
    public var icon: String {
        switch self {
        case .local: return "desktopcomputer"
        case .tailscale: return "network"
        case .custom: return "externaldrive.connected.to.line.below"
        }
    }
    
    public var color: String {
        switch self {
        case .local: return "green"
        case .tailscale: return "blue"
        case .custom: return "orange"
        }
    }
    
    /// Default timeout for this profile kind
    public var probeTimeout: TimeInterval {
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

public enum AuthMethod: Codable, Sendable, Hashable {
    case none                        // local only — no auth needed
    case bearerToken(String)         // pre-shared API key (stored reference, actual token in Keychain)
    
    enum CodingKeys: String, CodingKey {
        case type, token
    }
    
    public enum AuthType: String, Codable, Sendable {
        case none, bearerToken
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(AuthType.none, forKey: .type)
        case .bearerToken(let token):
            try container.encode(AuthType.bearerToken, forKey: .type)
            try container.encode(token, forKey: .token)
        }
    }
    
    public init(from decoder: Decoder) throws {
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
    public func apply(to request: inout URLRequest, tokenResolver: (String) -> String? = { _ in nil }) {
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
    public func applyToWebSocket(_ url: URL, tokenResolver: (String) -> String? = { _ in nil }) -> URL {
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
    public static var local: ConnectionProfile {
        try! ConnectionProfile(
            name: "Local",
            kind: .local,
            backendHost: "localhost",
            backendPort: defaultWebSocketPort,
            httpPort: defaultHTTPPort,
            webSocketPort: defaultWebSocketPort,
            useTLS: false,
            authMethod: .none,
            isDefault: true
        )
    }
    
    /// Template for Tailscale profile (host to be filled in)
    public static func tailscale(host: String, httpPort: Int = defaultHTTPPort, webSocketPort: Int = defaultWebSocketPort) -> ConnectionProfile {
        try! ConnectionProfile(
            name: "Tailscale (\(host))",
            kind: .tailscale,
            backendHost: host,
            backendPort: webSocketPort,
            httpPort: httpPort,
            webSocketPort: webSocketPort,
            useTLS: false,
            authMethod: .bearerToken("keychain-ref"),
            isDefault: false
        )
    }
}
