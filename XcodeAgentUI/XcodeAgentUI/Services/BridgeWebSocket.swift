import Foundation
import Observation

@Observable
final class BridgeWebSocket: @unchecked Sendable {
  var isConnected = false
  var messages: [BridgeEnvelope] = []
  var connectedClients: [BridgeClient] = []
  var lastError: String?
  var activeProfile: ConnectionProfile?

  var onMessageReceived: (@MainActor (BridgeEnvelope) -> Void)?
  var onConnectionChanged: (@MainActor (Bool) -> Void)?

  private var webSocket: URLSessionWebSocketTask?
  private var session: URLSession?
  private let maxMessages = 2000

  var host: String = "localhost"
  var port: Int = 9300

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

  /// Connect using a ConnectionProfile with optional auth token
  @MainActor
  func connect(profile: ConnectionProfile, role: ClientRole = .observer, name: String = "macos-ui", token: String? = nil) {
    disconnect()

    self.activeProfile = profile
    self.host = profile.backendHost
    self.port = profile.backendPort

    // Build WebSocket URL with auth if needed
    guard let url = profile.wsURL(role: role, name: name, token: token) else {
      lastError = "Invalid WebSocket URL for profile: \(profile.name)"
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

  /// Convenience method to connect with token resolution from Keychain
  @MainActor
  func connect(profile: ConnectionProfile, role: ClientRole = .observer, name: String = "macos-ui", tokenResolver: ((UUID) -> String?)? = nil) {
    var token: String?
    if case .bearerToken = profile.authMethod {
      token = tokenResolver?(profile.id) ?? ProfileStore.shared.loadToken(for: profile.id)
    }
    connect(profile: profile, role: role, name: name, token: token)
  }

  @MainActor
  func disconnect() {
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
    session = nil
    isConnected = false
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
