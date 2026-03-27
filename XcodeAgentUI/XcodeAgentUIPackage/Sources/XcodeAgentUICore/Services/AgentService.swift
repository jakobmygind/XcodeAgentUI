import Foundation
import Observation

@Observable @MainActor
public class AgentService {
  public var routerStatus = ServiceStatus(
    id: "router", name: "Router", state: .stopped, port: 3800)
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

  public func connectBridge() {
    bridgeWS.connect()
  }

  public func startRouter() {
    routerStatus.state = .starting
    bridgeStatus.state = .starting
    routerRunner.workingDirectory = agentDirectory
    let env = buildEnvironment()
    routerRunner.run(command: "npm", arguments: ["start"], environment: env)
  }

  public func stopRouter() {
    bridgeWS.disconnect()
    bridgeStatus.state = .stopped
    routerRunner.stop()
  }

  public func startBridge() {
    // The current backend exposes the WebSocket bridge from the main router process.
    // Keep this action as a convenience entrypoint in the UI, but start the main backend.
    startRouter()
  }

  public func stopBridge() {
    // There is no separate bridge daemon in the current local setup.
    // Stopping bridge means disconnecting the UI and stopping the shared backend.
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
    guard let provider = assignment.provider else { return }
    let runner = ProcessRunner(workingDirectory: agentDirectory)
    let env = buildEnvironment().merging([
      "AGENT_TYPE": provider.type.rawValue,
      "PROJECT": assignment.project,
      "ISSUE": assignment.ticketID,
    ]) { _, new in new }

    runner.run(
      command: "npm",
      arguments: ["run", "trigger:ui"],
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
    if port == bridgePort {
      return await bridgeWS.probeConnection(host: "localhost", port: port)
    }

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
      "BRIDGE_WS_PORT": "\(bridgePort)",
    ]

    let providerEnv = providerStore.buildProviderEnvironment()
    env.merge(providerEnv) { _, new in new }

    return env
  }
}
