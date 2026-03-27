import Foundation
import Network

/// Discovers OpenClaw backends via Bonjour/mDNS
@Observable
@MainActor
public final class LocalDiscovery {
    public enum DiscoveryState: Equatable {
        case idle
        case browsing
        case found([DiscoveredBackend])
        case error(String)
    }
    
    public var state: DiscoveryState = .idle
    public var discoveredBackends: [DiscoveredBackend] = []
    
    private var browser: NWBrowser?
    private let serviceType = "_openclaw._tcp"
    private let domain = "local."
    
    public init() {}

    /// Start browsing for OpenClaw services
    public func startBrowsing() {
        state = .browsing
        discoveredBackends = []
        
        let parameters = NWParameters.tcp
        browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: domain),
            using: parameters
        )
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleResults(results)
            }
        }
        
        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                switch newState {
                case .failed(let error):
                    self?.state = .error(error.localizedDescription)
                case .cancelled:
                    self?.state = .idle
                default:
                    break
                }
            }
        }
        
        browser?.start(queue: .global())
    }
    
    /// Stop browsing
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        state = .idle
    }
    
    /// Resolve a discovered service to get connection details
    public func resolve(_ backend: DiscoveredBackend) async throws -> ResolvedBackend {
        return try await withCheckedThrowingContinuation { continuation in
            guard case .bonjour(let endpoint) = backend.source else {
                continuation.resume(throwing: ConnectionError.discoveryFailed("Invalid backend source"))
                return
            }
            
            let connection = NWConnection(to: endpoint, using: .tcp)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Get the resolved endpoint
                    if let resolvedEndpoint = connection.currentPath?.remoteEndpoint {
                        if case .hostPort(let host, let port) = resolvedEndpoint {
                            let hostString: String
                            switch host {
                            case .ipv4(let address):
                                hostString = "\(address)"
                            case .ipv6(let address):
                                hostString = "[\(address)]"
                            case .name(let name, _):
                                hostString = name
                            default:
                                hostString = backend.name
                            }
                            
                            let resolved = ResolvedBackend(
                                name: backend.name,
                                host: hostString,
                                port: Int(port.rawValue),
                                source: backend.source
                            )
                            continuation.resume(returning: resolved)
                            connection.cancel()
                        } else {
                            continuation.resume(throwing: ConnectionError.discoveryFailed("Could not resolve endpoint"))
                            connection.cancel()
                        }
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                    connection.cancel()
                case .cancelled:
                    continuation.resume(throwing: ConnectionError.discoveryFailed("Resolution cancelled"))
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
            
            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                connection.cancel()
            }
        }
    }
    
    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var backends: [DiscoveredBackend] = []
        
        for result in results {
            if case .service(let name, let type, let domain, _) = result.endpoint {
                let backend = DiscoveredBackend(
                    name: name,
                    type: type,
                    domain: domain,
                    source: .bonjour(result.endpoint)
                )
                backends.append(backend)
            }
        }
        
        discoveredBackends = backends
        state = backends.isEmpty ? .browsing : .found(backends)
    }
    
}

/// A discovered backend service
public struct DiscoveredBackend: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let type: String
    public let domain: String
    public let source: DiscoverySource
    
    public enum DiscoverySource: Hashable, Sendable {
        case bonjour(NWEndpoint)
        case tailscale(TailscalePeer)
        
        public static func == (lhs: DiscoverySource, rhs: DiscoverySource) -> Bool {
            switch (lhs, rhs) {
            case (.bonjour, .bonjour), (.tailscale, .tailscale):
                return true
            default:
                return false
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .bonjour:
                hasher.combine("bonjour")
            case .tailscale:
                hasher.combine("tailscale")
            }
        }
    }
    
    public var displayName: String {
        name
    }
    
    public var icon: String {
        switch source {
        case .bonjour:
            return "wifi"
        case .tailscale:
            return "network"
        }
    }
}

/// A resolved backend with connection details
public struct ResolvedBackend: Sendable {
    public let name: String
    public let host: String
    public let port: Int
    public let source: DiscoveredBackend.DiscoverySource
    
    /// Convert to a connection profile
    /// - Returns: A connection profile, or nil if the resolved data is invalid
    public func toProfile(kind: ProfileKind = .local) -> ConnectionProfile? {
        try? ConnectionProfile(
            name: name,
            kind: kind,
            backendHost: host,
            backendPort: port,
            useTLS: false,
            authMethod: kind == .local ? .none : .bearerToken("keychain-ref"),
            isDefault: false
        )
    }
}
