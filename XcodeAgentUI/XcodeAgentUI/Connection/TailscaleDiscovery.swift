import Foundation

/// Discovers OpenClaw backends via Tailscale local API
@Observable
@MainActor
final class TailscaleDiscovery {
    enum DiscoveryState: Equatable {
        case idle
        case discovering
        case found([TailscalePeer])
        case error(String)
    }
    
    var state: DiscoveryState = .idle
    var discoveredPeers: [TailscalePeer] = []
    var responsiveBackends: [TailscalePeer] = []
    
    private let localAPIURL = URL(string: "http://127.0.0.1:41112/localapi/v0/status")!
    private var probeTask: Task<Void, Never>?
    
    /// Check if Tailscale is running by querying the local API
    func isTailscaleRunning() async -> Bool {
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
    func discoverPeers(probeForBackends: Bool = true, port: Int = 9300) async {
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
    func probeForAgent(peer: TailscalePeer, port: Int = 9300) async -> Bool {
        let url = URL(string: "http://\(peer.tailscaleIP):\(port)/api/health")!
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
    func stopDiscovery() {
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

struct TailscalePeer: Identifiable, Hashable, Sendable {
    let id = UUID()
    let hostname: String
    let tailscaleIP: String
    let magicDNS: String
    let os: String
    let online: Bool
    let isSelf: Bool
    
    var displayName: String {
        if isSelf {
            return "\(hostname) (This Machine)"
        }
        return hostname
    }
    
    var shortDNS: String {
        // Remove trailing dot and tailnet suffix if present
        magicDNS
            .replacingOccurrences(of: ".$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: " ")
            .components(separatedBy: " ")
            .first ?? hostname
    }
    
    /// Convert to a connection profile
    func toProfile(port: Int = 9300) -> ConnectionProfile {
        ConnectionProfile(
            name: "Tailscale: \(hostname)",
            kind: .tailscale,
            backendHost: tailscaleIP,
            backendPort: port,
            useTLS: false,
            authMethod: .bearerToken("keychain-ref"),
            isDefault: false
        )
    }
}
