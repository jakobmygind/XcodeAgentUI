import Foundation
import Observation

private func normalizedBackendHostValue(_ host: String) -> String {
  let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return "localhost" }
  return trimmed
}

@Observable @MainActor
public class AgentService {
  public enum BackendMode: String, CaseIterable, Codable, Sendable {
    case remote
    case localDebug

    public var displayName: String {
      switch self {
      case .remote: return "Remote backend"
      case .localDebug: return "Local debug backend"
      }
    }

    public var description: String {
      switch self {
      case .remote:
        return "Recommended. The backend runs on the Mac mini and this app connects over Tailscale."
      case .localDebug:
        return "Debug only. Starts the Node backend on this Mac from a local checkout."
      }
    }
  }

  public var routerStatus = ServiceStatus(
    id: "router", name: "Backend API", state: .stopped, port: 3800)
  public var bridgeStatus = ServiceStatus(
    id: "bridge", name: "Bridge", state: .stopped, port: 9300)
  public var workerCount: Int = 0

  let routerRunner: ProcessRunner
  let bridgeRunner: ProcessRunner

  public let bridgeWS = BridgeWebSocket()

  public var sessionManager: SessionManager

  public let providerStore = ProviderStore()

  public var routerLogs: [String] { routerRunner.output }
  public var bridgeLogs: [String] { bridgeRunner.output }
  public var bridgeConnected: Bool { bridgeWS.isConnected }
  public var connectedBridgeClients: [BridgeClient] { bridgeWS.connectedClients }
  public var sharedBridgeWebSocket: BridgeWebSocket { bridgeWS }

  public let queueManager = QueueManager()

  public let metricsStore = MetricsStore()

  public var backendMode: BackendMode {
    didSet {
      UserDefaults.standard.set(backendMode.rawValue, forKey: "backendMode")
      if backendMode == .remote {
        stopLocalProcessesIfNeeded()
      }
    }
  }

  public var backendHost: String {
    didSet {
      let normalized = normalizedBackendHostValue(backendHost)
      UserDefaults.standard.set(normalized, forKey: "backendHost")
      bridgeWS.host = normalized
    }
  }

  public var agentDirectory: String {
    didSet { UserDefaults.standard.set(agentDirectory, forKey: "agentDirectory") }
  }
  public var routerPort: Int = 3800 {
    didSet { UserDefaults.standard.set(routerPort, forKey: "routerPort") }
  }
  public var bridgePort: Int = 9300 {
    didSet {
      UserDefaults.standard.set(bridgePort, forKey: "bridgePort")
      bridgeWS.port = bridgePort
    }
  }

  public init() {
    let savedDir =
      UserDefaults.standard.string(forKey: "agentDirectory")
      ?? NSHomeDirectory() + "/.openclaw/workspace/xcode-agent"
    self.agentDirectory = savedDir
    self.routerRunner = ProcessRunner(workingDirectory: savedDir)
    self.bridgeRunner = ProcessRunner(workingDirectory: savedDir)
    self.sessionManager = SessionManager(bridgeWS: bridgeWS)

    self.backendMode = BackendMode(rawValue: UserDefaults.standard.string(forKey: "backendMode") ?? "remote") ?? .remote
    self.backendHost = normalizedBackendHostValue(UserDefaults.standard.string(forKey: "backendHost") ?? "localhost")

    if let port = UserDefaults.standard.object(forKey: "routerPort") as? Int {
      self.routerPort = port
    }
    if let port = UserDefaults.standard.object(forKey: "bridgePort") as? Int {
      self.bridgePort = port
      self.bridgeWS.port = port
    }

    self.bridgeWS.host = backendHost

    setupObservers()
    setupQueueDispatch()
  }

  public var usesRemoteBackend: Bool { backendMode == .remote }
  public var usesLocalDebugBackend: Bool { backendMode == .localDebug }

  private func setupObservers() {
    routerRunner.onRunningChanged = { [weak self] running in
      guard let self else { return }
      if self.usesLocalDebugBackend {
        self.routerStatus.state = running ? .running : .stopped
      }
    }

    bridgeRunner.onRunningChanged = { [weak self] running in
      guard let self else { return }
      if self.usesLocalDebugBackend {
        self.bridgeStatus.state = running ? .running : .stopped
        if running {
          Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.bridgeWS.connect()
          }
        }
      }
    }

  }

  private func setupQueueDispatch() {
    queueManager.onDispatch = { [weak self] ticket in
      guard let self = self,
        let provider = self.providerStore.providers.first(where: {
          $0.type.rawValue == ticket.providerType
        })
      else { return }

      let assignment = TicketAssignment(
        provider: provider,
        ticketID: ticket.ticketID,
        project: ticket.project,
        model: ticket.model == "Opus" ? .opus : .sonnet
      )
      self.assignTicket(assignment)
    }
  }

  // MARK: - Service Control

  public func connectBridge() {
    bridgeWS.host = normalizedBackendHostValue(backendHost)
    bridgeWS.port = bridgePort
    bridgeWS.connect()
  }

  public func startRouter() {
    if usesRemoteBackend {
      routerStatus.state = .starting
      bridgeStatus.state = .starting
      checkHealth()
      connectBridge()
      return
    }

    routerStatus.state = .starting
    bridgeStatus.state = .starting
    routerRunner.workingDirectory = agentDirectory
    bridgeRunner.workingDirectory = agentDirectory
    let env = buildEnvironment()
    routerRunner.run(command: "npm", arguments: ["run", "router"], environment: env)
    bridgeRunner.run(command: "npm", arguments: ["run", "bridge"], environment: env)
  }

  public func stopRouter() {
    bridgeWS.disconnect()
    if usesRemoteBackend {
      routerStatus.state = .stopped
      bridgeStatus.state = .stopped
      return
    }

    bridgeStatus.state = .stopped
    routerRunner.stop()
    bridgeRunner.stop()
  }

  public func startBridge() {
    if usesRemoteBackend {
      bridgeStatus.state = .starting
      connectBridge()
      checkHealth()
      return
    }

    // Router and bridge are independent processes; startRouter() launches both.
    // If router is already running but bridge died, restart just the bridge.
    if bridgeStatus.state == .stopped || bridgeStatus.state == .error {
      if routerStatus.state == .stopped {
        startRouter()
      } else {
        bridgeStatus.state = .starting
        bridgeRunner.workingDirectory = agentDirectory
        bridgeRunner.run(command: "npm", arguments: ["run", "bridge"], environment: buildEnvironment())
      }
    }
  }

  public func stopBridge() {
    if usesRemoteBackend {
      bridgeWS.disconnect()
      bridgeStatus.state = .stopped
      return
    }

    stopRouter()
  }

  public func startAll() {
    startRouter()
  }

  public func stopAll() {
    stopRouter()
  }

  // MARK: - Ticket Assignment

  public func assignTicket(_ assignment: TicketAssignment) {
    if usesRemoteBackend {
      Task {
        await triggerRemoteTicket(assignment)
      }
      return
    }

    guard let provider = assignment.provider else { return }
    let runner = ProcessRunner(workingDirectory: agentDirectory)
    let env = buildEnvironment().merging([
      "AGENT_TYPE": provider.type.rawValue,
      "PROJECT": assignment.project,
      "ISSUE": assignment.ticketID,
    ]) { _, new in new }

    runner.run(
      command: "npm",
      arguments: ["run", "router:trigger", "--", provider.type.rawValue, assignment.project, assignment.ticketID],
      environment: env
    )
  }

  // MARK: - Health Checks

  public func checkHealth() {
    Task { [weak self] in
      guard let self else { return }
      let routerHealthy = await self.checkServiceHealth(port: self.routerPort)
      let bridgeHealthy = await self.checkServiceHealth(port: self.bridgePort)

      await MainActor.run {
        self.routerStatus.state = routerHealthy ? .running : .stopped
        self.bridgeStatus.state = bridgeHealthy ? .running : .stopped
      }
    }
  }

  private func checkServiceHealth(port: Int) async -> Bool {
    if port == bridgePort {
      return await bridgeWS.probeConnection(host: normalizedBackendHostValue(backendHost), port: port)
    }

    let host = normalizedBackendHostValue(backendHost)
    guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
    do {
      let (_, response) = try await URLSession.shared.data(from: url)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  // MARK: - Environment

  private func buildEnvironment() -> [String: String] {
    var env: [String: String] = [
      "PORT": "\(routerPort)",
      "BRIDGE_WS_PORT": "\(bridgePort)",
    ]

    let providerEnv = providerStore.buildProviderEnvironment()
    env.merge(providerEnv) { _, new in new }

    return env
  }

  private func stopLocalProcessesIfNeeded() {
    routerRunner.stop()
    bridgeRunner.stop()
  }

  private func triggerRemoteTicket(_ assignment: TicketAssignment) async {
    guard let provider = assignment.provider else { return }

    let payload: [String: Any] = [
      "provider": provider.type.rawValue,
      "project": assignment.project,
      "ticketID": assignment.ticketID,
      "model": assignment.model.rawValue,
    ]

    let candidatePaths = ["/trigger", "/api/trigger"]
    let host = normalizedBackendHostValue(backendHost)

    for path in candidatePaths {
      guard let url = URL(string: "http://\(host):\(routerPort)\(path)") else { continue }
      var request = URLRequest(url: url, timeoutInterval: 10)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
          return
        }
      } catch {
        continue
      }
    }

    sessionManager.activeSession?.addFeedMessage(
      FeedMessage(
        type: .error,
        content: "Could not trigger remote backend on \(host):\(routerPort). Ensure the Mac mini backend exposes POST /trigger or /api/trigger.",
        from: "system"
      ))
  }
}
