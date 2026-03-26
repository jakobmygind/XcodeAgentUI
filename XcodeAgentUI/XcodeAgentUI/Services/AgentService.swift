import Foundation
import Observation

@Observable @MainActor
class AgentService: @unchecked Sendable {
  var routerStatus = ServiceStatus(
    id: "router", name: "Router", state: .stopped, port: 3800)
  var bridgeStatus = ServiceStatus(
    id: "bridge", name: "Bridge", state: .stopped, port: 9300)
  var workerCount: Int = 0

  let routerRunner: ProcessRunner
  let bridgeRunner: ProcessRunner

  let bridgeWS = BridgeWebSocket()

  var sessionManager: SessionManager

  let providerStore = ProviderStore()

  let queueManager = QueueManager()

  let metricsStore = MetricsStore()

  var agentDirectory: String {
    didSet { UserDefaults.standard.set(agentDirectory, forKey: "agentDirectory") }
  }
  var routerPort: Int = 3800 {
    didSet { UserDefaults.standard.set(routerPort, forKey: "routerPort") }
  }
  var bridgePort: Int = 9300 {
    didSet {
      UserDefaults.standard.set(bridgePort, forKey: "bridgePort")
      bridgeWS.port = bridgePort
    }
  }

  init() {
    let savedDir =
      UserDefaults.standard.string(forKey: "agentDirectory")
      ?? NSHomeDirectory() + "/.openclaw/workspace/xcode-agent"
    self.agentDirectory = savedDir
    self.routerRunner = ProcessRunner(workingDirectory: savedDir)
    self.bridgeRunner = ProcessRunner(workingDirectory: savedDir)
    self.sessionManager = SessionManager(bridgeWS: bridgeWS)

    if let port = UserDefaults.standard.object(forKey: "routerPort") as? Int {
      self.routerPort = port
    }
    if let port = UserDefaults.standard.object(forKey: "bridgePort") as? Int {
      self.bridgePort = port
      self.bridgeWS.port = port
    }

    setupObservers()
    setupQueueDispatch()
  }

  private func setupObservers() {
    routerRunner.onRunningChanged = { [weak self] running in
      self?.routerStatus.state = running ? .running : .stopped
    }

    bridgeRunner.onRunningChanged = { [weak self] running in
      self?.bridgeStatus.state = running ? .running : .stopped
      if running {
        Task { @MainActor [weak self] in
          try? await Task.sleep(for: .seconds(1.5))
          self?.bridgeWS.connect()
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

  func startRouter() {
    routerStatus.state = .starting
    routerRunner.workingDirectory = agentDirectory
    let env = buildEnvironment()
    routerRunner.run(command: "npm", arguments: ["run", "router"], environment: env)
  }

  func stopRouter() {
    routerRunner.stop()
  }

  func startBridge() {
    bridgeStatus.state = .starting
    bridgeRunner.workingDirectory = agentDirectory
    let env = buildEnvironment()
    bridgeRunner.run(command: "npm", arguments: ["run", "bridge"], environment: env)
  }

  func stopBridge() {
    bridgeWS.disconnect()
    bridgeRunner.stop()
  }

  func startAll() {
    startBridge()
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      self?.startRouter()
    }
  }

  func stopAll() {
    stopRouter()
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      self?.stopBridge()
    }
  }

  // MARK: - Ticket Assignment

  func assignTicket(_ assignment: TicketAssignment) {
    guard let provider = assignment.provider else { return }
    let runner = ProcessRunner(workingDirectory: agentDirectory)
    let env = buildEnvironment()

    runner.run(
      command: "npm",
      arguments: [
        "run", "router:trigger", "--",
        provider.type.rawValue,
        assignment.project,
        assignment.ticketID,
      ],
      environment: env
    )
  }

  // MARK: - Health Checks

  func checkHealth() {
    Task { [weak self] in
      guard let self else { return }
      let routerHealthy = await self.checkServiceHealth(port: self.routerPort)
      let bridgeHealthy = await self.checkServiceHealth(port: self.bridgePort)

      await MainActor.run {
        if self.routerRunner.isRunning {
          self.routerStatus.state = routerHealthy ? .running : .starting
        }
        if self.bridgeRunner.isRunning {
          self.bridgeStatus.state = bridgeHealthy ? .running : .starting
        }
      }
    }
  }

  private func checkServiceHealth(port: Int) async -> Bool {
    guard let url = URL(string: "http://localhost:\(port)/health") else { return false }
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
      "BRIDGE_PORT": "\(bridgePort)",
    ]

    let providerEnv = providerStore.buildProviderEnvironment()
    env.merge(providerEnv) { _, new in new }

    return env
  }
}
