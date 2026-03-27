import Foundation
import Observation

@Observable
public final class BridgeWebSocket: @unchecked Sendable {
  public var isConnected = false
  public var messages: [BridgeEnvelope] = []
  public var connectedClients: [BridgeClient] = []
  public var lastError: String?
  public var activeProfile: ConnectionProfile?

  public var onMessageReceived: (@MainActor (BridgeEnvelope) -> Void)?
  public var onConnectionChanged: (@MainActor (Bool) -> Void)?

  private var webSocket: URLSessionWebSocketTask?
  private var session: URLSession?
  private let maxMessages = 2000

  public var host: String = "localhost"
  public var port: Int = 9300

  public init() {}

  @MainActor
  public func connect(role: ClientRole = .observer, name: String = "macos-ui") {
    disconnect()

    let urlString = "ws://\(host):\(port)?role=\(role.rawValue)&name=\(name)"
    guard let url = URL(string: urlString) else {
      lastError = "Invalid URL: \(urlString)"
      return
    }

    session = URLSession(configuration: .default)
    webSocket = session?.webSocketTask(with: url)
    webSocket?.resume()

    lastError = nil
    receiveMessage()
  }

  /// Connect using a ConnectionProfile with optional auth token
  @MainActor
  public func connect(profile: ConnectionProfile, role: ClientRole = .observer, name: String = "macos-ui", token: String? = nil) {
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
  public func connect(profile: ConnectionProfile, role: ClientRole = .observer, name: String = "macos-ui", tokenResolver: ((UUID) -> String?)? = nil) {
    var token: String?
    if case .bearerToken = profile.authMethod {
      token = tokenResolver?(profile.id) ?? ProfileStore.shared.loadToken(for: profile.id)
    }
    connect(profile: profile, role: role, name: name, token: token)
  }

  @MainActor
  public func disconnect() {
    webSocket?.cancel(with: .goingAway, reason: nil)
    webSocket = nil
    session = nil
    isConnected = false
    onConnectionChanged?(false)
  }

  @MainActor
  public func send(type: String, payload: String) {
    let command: [String: Any] = [
      "command": payload,
      "target": type == "human_command" ? NSNull() : type,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: command),
      let str = String(data: data, encoding: .utf8)
    else { return }

    webSocket?.send(.string(str)) { [weak self] error in
      Task { @MainActor [weak self] in
        if let error {
          self?.isConnected = false
          self?.lastError = error.localizedDescription
          self?.onConnectionChanged?(false)
        } else {
          self?.lastError = nil
        }
      }
    }
  }

  private func receiveMessage() {
    webSocket?.receive { [weak self] result in
      switch result {
      case .success(let message):
        Task { @MainActor [weak self] in
          guard let self else { return }
          if !self.isConnected {
            self.isConnected = true
            self.onConnectionChanged?(true)
          }
          self.lastError = nil
        }

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

  public nonisolated func probeConnection(host: String, port: Int) async -> Bool {
    guard let url = URL(string: "ws://\(host):\(port)") else { return false }

    let session = URLSession(configuration: .default)
    let socket = session.webSocketTask(with: url)
    socket.resume()
    defer {
      socket.cancel(with: .goingAway, reason: nil)
      session.invalidateAndCancel()
    }

    do {
      _ = try await socket.receive()
      return true
    } catch {
      return false
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
