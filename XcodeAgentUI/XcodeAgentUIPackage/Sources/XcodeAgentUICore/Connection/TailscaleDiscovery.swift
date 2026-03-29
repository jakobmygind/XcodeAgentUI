import Foundation

/// Discovers OpenClaw backends via Tailscale local API
@Observable
@MainActor
public final class TailscaleDiscovery {
    public enum DiscoveryState: Equatable {
        case idle
        case discovering
        case found([TailscalePeer])
        case error(String)
    }
    
    public var state: DiscoveryState = .idle
    public var discoveredPeers: [TailscalePeer] = []
    public var responsiveBackends: [TailscalePeer] = []
    
    private let localAPIURL = URL(string: "http://127.0.0.1:41112/localapi/v0/status")!
    private var probeTask: Task<Void, Never>?
    
    public init() {}

    /// Check if Tailscale is running by querying the local API
    public func isTailscaleRunning() async -> Bool {
        var request = URLRequest(url: localAPIURL, timeoutInterval: 2)
        request.httpMethod = "GET"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Discover Tailscale peers and probe for OpenClaw backends
    public func discoverPeers(probeForBackends: Bool = true, port: Int = ConnectionProfile.defaultHTTPPort) async {
        state = .discovering
        discoveredPeers = []
        responsiveBackends = []
        
        // Check if Tailscale is running
        guard await isTailscaleRunning() else {
            state = .error("Tailscale is not running")
            return
        }
        
        // Fetch peers from local API
        do {
            let peers = try await fetchPeers()
            discoveredPeers = peers
            
            if probeForBackends {
                // Probe each peer for OpenClaw backend
                let backends = await probePeersForBackends(peers: peers, port: port)
                responsiveBackends = backends
                state = backends.isEmpty ? .found(peers) : .found(backends)
            } else {
                state = .found(peers)
            }
            
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// Fetch peers from Tailscale local API
    private func fetchPeers() async throws -> [TailscalePeer] {
        var request = URLRequest(url: localAPIURL, timeoutInterval: 5)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConnectionError.tailscaleNotRunning
        }
        
        let status = try JSONDecoder().decode(TailscaleStatus.self, from: data)
        
        // Filter to online macOS/Linux peers (potential backends)
        return status.peers.values
            .filter { $0.online }
            .sorted { $0.hostName < $1.hostName }
            .map { peer in
                TailscalePeer(
                    hostname: peer.hostName,
                    tailscaleIP: peer.tailAddrs.first ?? "",
                    magicDNS: peer.dnsName,
                    os: peer.os,
                    online: peer.online,
                    isSelf: peer.sshHostKeys != nil  // Rough heuristic for self
                )
            }
    }
    
    /// Probe peers to find which ones are running OpenClaw backends
    private func probePeersForBackends(peers: [TailscalePeer], port: Int) async -> [TailscalePeer] {
        await withTaskGroup(of: TailscalePeer?.self) { group in
            for peer in peers {
                group.addTask {
                    let hasBackend = await self.probeForAgent(peer: peer, port: port)
                    return hasBackend ? peer : nil
                }
            }
            
            var backends: [TailscalePeer] = []
            for await peer in group {
                if let peer = peer {
                    backends.append(peer)
                }
            }
            return backends
        }
    }
    
    /// Probe a specific peer for OpenClaw backend
    public func probeForAgent(peer: TailscalePeer, port: Int = ConnectionProfile.defaultHTTPPort) async -> Bool {
        let url = URL(string: "http://\(peer.tailscaleIP):\(port)/health")!
        let request = URLRequest(url: url, timeoutInterval: 3)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Stop discovery
    public func stopDiscovery() {
        probeTask?.cancel()
        probeTask = nil
        state = .idle
    }
}

// MARK: - Tailscale API Response Types

struct TailscaleStatus: Codable {
    let version: String
    let backendState: String
    let selfPeer: TailscaleSelfPeer
    let peers: [String: TailscalePeerInfo]
    
    enum CodingKeys: String, CodingKey {
        case version
        case backendState = "BackendState"
        case selfPeer = "Self"
        case peers = "Peer"
    }
}

struct TailscaleSelfPeer: Codable {
    let id: String
    let hostName: String
    let dnsName: String
    let tailAddrs: [String]
    let addrs: [String]
    let curAddr: String
    let relay: String
    let os: String
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailAddrs = "TailAddrs"
        case addrs = "Addrs"
        case curAddr = "CurAddr"
        case relay = "Relay"
        case os = "OS"
    }
}

struct TailscalePeerInfo: Codable {
    let id: String
    let hostName: String
    let dnsName: String
    let tailAddrs: [String]
    let addrs: [String]?
    let curAddr: String?
    let relay: String?
    let online: Bool
    let os: String
    let sshHostKeys: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case tailAddrs = "TailAddrs"
        case addrs = "Addrs"
        case curAddr = "CurAddr"
        case relay = "Relay"
        case online = "Online"
        case os = "OS"
        case sshHostKeys = "SSH_HostKeys"
    }
}

// MARK: - Peer Model

public struct TailscalePeer: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let hostname: String
    public let tailscaleIP: String
    public let magicDNS: String
    public let os: String
    public let online: Bool
    public let isSelf: Bool
    
    public init(
        hostname: String,
        tailscaleIP: String,
        magicDNS: String,
        os: String,
        online: Bool,
        isSelf: Bool
    ) {
        self.hostname = hostname
        self.tailscaleIP = tailscaleIP
        self.magicDNS = magicDNS
        self.os = os
        self.online = online
        self.isSelf = isSelf
    }
    
    public var displayName: String {
        if isSelf {
            return "\(hostname) (This Machine)"
        }
        return hostname
    }
    
    public var shortDNS: String {
        // Remove trailing dot and tailnet suffix if present
        magicDNS
            .replacingOccurrences(of: ".$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: " ")
            .components(separatedBy: " ")
            .first ?? hostname
    }
    
    /// Convert to a connection profile
    /// - Returns: A connection profile, or nil if the peer data is invalid
    public func toProfile(httpPort: Int = ConnectionProfile.defaultHTTPPort, webSocketPort: Int = ConnectionProfile.defaultWebSocketPort) -> ConnectionProfile? {
        try? ConnectionProfile(
            name: "Tailscale: \(hostname)",
            kind: .tailscale,
            backendHost: magicDNS.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? tailscaleIP : magicDNS.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            backendPort: webSocketPort,
            httpPort: httpPort,
            webSocketPort: webSocketPort,
            useTLS: false,
            authMethod: .bearerToken("keychain-ref"),
            isDefault: false
        )
    }
}
