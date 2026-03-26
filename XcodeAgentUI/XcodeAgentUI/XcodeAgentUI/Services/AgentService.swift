import Combine
import Foundation

/// Central service managing all Xcode Agent Runner components
class AgentService: ObservableObject {
  // Service statuses
  @Published var routerStatus = ServiceStatus(
    id: "router", name: "Router", state: .stopped, port: 3800)
  @Published var bridgeStatus = ServiceStatus(
    id: "bridge", name: "Bridge", state: .stopped, port: 9300)
  @Published var workerCount: Int = 0

  // Process runners
  let routerRunner: ProcessRunner
  let bridgeRunner: ProcessRunner

  // Bridge WebSocket
  let bridgeWS = BridgeWebSocket()

  // Session manager (shared across views)
  @Published var sessionManager: SessionManager

  // Provider management
  let providerStore = ProviderStore()

  // Queue management
  let queueManager = QueueManager()

  // Performance metrics
  let metricsStore = MetricsStore()

  // Configuration
  @Published var agentDirectory: String {
    didSet { UserDefaults.standard.set(agentDirectory, forKey: "agentDirectory") }
  }
  @Published var routerPort: Int = 3800 {
    didSet { UserDefaults.standard.set(routerPort, forKey: "routerPort") }
  }
  @Published var bridgePort: Int = 9300 {
    didSet {
      UserDefaults.standard.set(bridgePort, forKey: "bridgePort")
      bridgeWS.port = bridgePort
    }
  }

  private var cancellables = Set<AnyCancellable>()
  private var healthTimer: Timer?

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
    routerRunner.$isRunning
      .receive(on: DispatchQueue.main)
      .sink { [weak self] running in
        self?.routerStatus.state = running ? .running : .stopped
      }
      .store(in: &cancellables)

    bridgeRunner.$isRunning
      .receive(on: DispatchQueue.main)
      .sink { [weak self] running in
        self?.bridgeStatus.state = running ? .running : .stopped
        if running {
          // Auto-connect WebSocket when bridge starts
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self?.bridgeWS.connect()
          }
        }
      }
      .store(in: &cancellables)
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
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      self.startRouter()
    }
  }

  func stopAll() {
    stopRouter()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      self.stopBridge()
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
    checkServiceHealth(port: routerPort) { [weak self] healthy in
      DispatchQueue.main.async {
        if self?.routerRunner.isRunning == true {
          self?.routerStatus.state = healthy ? .running : .starting
        }
      }
    }

    checkServiceHealth(port: bridgePort) { [weak self] healthy in
      DispatchQueue.main.async {
        if self?.bridgeRunner.isRunning == true {
          self?.bridgeStatus.state = healthy ? .running : .starting
        }
      }
    }
  }

  private func checkServiceHealth(port: Int, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: "http://localhost:\(port)/health") else {
      completion(false)
      return
    }
    URLSession.shared.dataTask(with: url) { _, response, _ in
      let httpResponse = response as? HTTPURLResponse
      completion(httpResponse?.statusCode == 200)
    }.resume()
  }

  // MARK: - Environment

  private func buildEnvironment() -> [String: String] {
    var env: [String: String] = [
      "PORT": "\(routerPort)",
      "BRIDGE_PORT": "\(bridgePort)",
    ]

    // Merge provider credentials from ProviderStore
    let providerEnv = providerStore.buildProviderEnvironment()
    env.merge(providerEnv) { _, new in new }

    return env
  }
}
