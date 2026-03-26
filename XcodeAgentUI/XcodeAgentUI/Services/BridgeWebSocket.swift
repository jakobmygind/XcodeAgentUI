import Foundation
import Observation

@Observable
final class BridgeWebSocket: @unchecked Sendable {
  var isConnected = false
  var messages: [BridgeEnvelope] = []
  var connectedClients: [BridgeClient] = []
  var lastError: String?

  var onMessageReceived: (@MainActor (BridgeEnvelope) -> Void)?
  var onConnectionChanged: (@MainActor (Bool) -> Void)?

  private var webSocket: URLSessionWebSocketTask?
  private var session: URLSession?
  private let maxMessages = 2000

  var host: String = "localhost"
  var port: Int = 9300
  
  /// The active connection profile (set when using profile-based connection)
  private(set) var activeProfile: ConnectionProfile?
  
  /// Auth token for the current connection
  private var authToken: String?

  @MainActor
  func connect(role: ClientRole = .observer, name: String = "macos-ui") {
    disconnect()

    let urlString = "ws://\(host):\(port)?role=\(role.rawValue)&name=\(name)"
    guard let url = URL(string: urlString) else {
      lastError = "Invalid URL: \(urlString)"
      return
    }

    session = URLSession(configuration: .default)
    webSocket = session?.webSocketTask(with: url)
    webSocket?.resume()

    isConnected = true
    lastError = nil
    onConnectionChanged?(true)

    receiveMessage()
  }
  
  /// Connect using a ConnectionProfile
  /// - Note: Auth token is sent via Authorization header, not URL query parameter, for security
  @MainActor
  func connect(using profile: ConnectionProfile, token: String? = nil, role: ClientRole = .observer, name: String = "macos-ui") {
    guard profile.isConfigured else {
      lastError = "Profile '\(profile.name)' is not configured"
      return
    }
    
    guard let wsURL = profile.wsURL else {
      lastError = "Profile '\(profile.name)' does not have a WebSocket URL"
      return
    }
    
    activeProfile = profile
    authToken = token
    
    // Update legacy host/port for backward compatibility
    host = profile.backendHost
    port = profile.backendPort
    
    // Build WebSocket URL with query parameters (auth via header, not URL)
    guard var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: true) else {
      lastError = "Invalid URL components from profile"
      return
    }
    
    var queryItems = [
      URLQueryItem(name: "role", value: role.rawValue),
      URLQueryItem(name: "name", value: name)
    ]
    
    components.queryItems = queryItems
    
    guard let finalURL = components.url else {
      lastError = "Invalid URL constructed from profile"
      return
    }
    
    disconnect()
    
    // Create URL request with auth header (more secure than query parameter)
    var request = URLRequest(url: finalURL)
    request.setValue("Upgrade", forHTTPHeaderField: "Connection")
    request.setValue("websocket", forHTTPHeaderField: "Upgrade")
    if let token = token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    
    session = URLSession(configuration: .default)
    webSocket = session?.webSocketTask(with: request)
    webSocket?.resume()
    
    isConnected = true
    lastError = nil
    onConnectionChanged?(true)
    
    receiveMessage()
  }
  
  /// Connect using ConnectionManager (recommended approach)
  @MainActor
  func connect(with manager: ConnectionManager, role: ClientRole = .observer, name: String = "macos-ui") async {
    guard case .connected(let profile) = manager.state else {
      lastError = "ConnectionManager is not in connected state"
      return
    }
    
    let token = await manager.authorizationHeader()
    connect(using: profile, token: token, role: role, name: name)
  }

  @MainActor
  func disconnect() {
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
    session = nil
    isConnected = false
    activeProfile = nil
    authToken = nil
    onConnectionChanged?(false)
  }

  @MainActor
  func send(type: String, payload: String) {
    let envelope: [String: Any] = [
      "type": type,
      "from": "human",
      "ts": ISO8601DateFormatter().string(from: Date()),
      "payload": payload,
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: envelope),
      let str = String(data: data, encoding: .utf8)
    else { return }

    webSocket?.send(.string(str)) { [weak self] error in
      if let error = error {
        Task { @MainActor [weak self] in
          self?.lastError = error.localizedDescription
        }
      }
    }
  }

  private func receiveMessage() {
    webSocket?.receive { [weak self] result in
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self?.handleMessage(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            self?.handleMessage(text)
          }
        @unknown default:
          break
        }
        self?.receiveMessage()

      case .failure(let error):
        Task { @MainActor [weak self] in
          self?.isConnected = false
          self?.lastError = error.localizedDescription
          self?.onConnectionChanged?(false)
        }
      }
    }
  }

  private func handleMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
      let envelope = try? JSONDecoder().decode(BridgeEnvelope.self, from: data)
    else { return }

    Task { @MainActor [weak self] in
      guard let self else { return }
      self.messages.append(envelope)
      if self.messages.count > self.maxMessages {
        self.messages.removeFirst(self.messages.count - self.maxMessages)
      }

      if envelope.type == "system" {
        if let dict = envelope.payload.value as? [String: Any],
          let event = dict["event"] as? String
        {
          if event == "client_connected",
            let role = dict["role"] as? String,
            let name = dict["name"] as? String
          {
            self.connectedClients.append(BridgeClient(role: role, name: name))
          } else if event == "client_disconnected",
            let name = dict["name"] as? String
          {
            self.connectedClients.removeAll { $0.name == name }
          }
        }
      }

      self.onMessageReceived?(envelope)
    }
  }
}

// MARK: - ConnectionProfile Convenience Methods

extension BridgeWebSocket {
  /// Quick connect to local backend
  @MainActor
  func connectToLocal(role: ClientRole = .observer, name: String = "macos-ui") {
    let profile = ConnectionProfile.local
    connect(using: profile, role: role, name: name)
  }
  
  /// Reconnect using the same profile
  @MainActor
  func reconnect() {
    if let profile = activeProfile {
      connect(using: profile, token: authToken)
    } else {
      connect()
    }
  }
  
  /// The currently active profile, if any
  var currentProfile: ConnectionProfile? {
    activeProfile
  }
}
