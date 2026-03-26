import Foundation

// MARK: - Mock Agent Service

@MainActor
final class MockAgentService: AgentService {

  static let shared = MockAgentService()

  override init() {
    super.init()
    seedAllMockData()
  }

  private func seedAllMockData() {
    routerStatus = ServiceStatus(id: "router", name: "Router", state: .running, port: 3800)
    bridgeStatus = ServiceStatus(id: "bridge", name: "Bridge", state: .running, port: 9300)
    workerCount = 3

    let session = AgentSession(ticketID: "MOBILE-2847", project: "ios-shopping-app")
    session.criteria = MockTicketData.sampleCriteria
    session.feedMessages = MockTicketData.sampleFeedMessages
    session.diffChunks = MockTicketData.sampleDiffChunks
    session.tokensUsed = 45_200
    session.tokenLimit = 100_000
    sessionManager.activeSession = session

    seedQueue()
    metricsStore.seedDemoData()
    seedProviders()
  }

  private func seedQueue() {
    for ticket in MockTicketData.sampleQueueTickets {
      queueManager.addTicket(ticket)
    }
  }

  private func seedProviders() {
    providerStore.addProvider(Provider(
      id: "github",
      name: "GitHub – openclaw",
      type: .github,
      baseURL: "https://api.github.com",
      defaultProject: "openclaw/xcode-agent"
    ))
    providerStore.addProvider(Provider(
      id: "jira",
      name: "Jira – Mobile Team",
      type: .jira,
      baseURL: "https://team.atlassian.net",
      defaultProject: "MOBILE"
    ))
  }
}

// MARK: - Mock Session Manager

enum MockSessionManager {
  @MainActor
  static func create() -> SessionManager {
    let mockWS = BridgeWebSocket()
    let manager = SessionManager(bridgeWS: mockWS)

    let session = AgentSession(ticketID: "INFRA-1024", project: "deploy-pipeline")
    session.criteria = [
      AcceptanceCriterion(text: "Add retry logic to deploy step"),
      AcceptanceCriterion(text: "Handle timeout errors gracefully", isCompleted: true),
      AcceptanceCriterion(text: "Update integration tests"),
    ]
    session.feedMessages = [
      FeedMessage(type: .system, content: "Session started for INFRA-1024", from: "system"),
      FeedMessage(
        type: .output, content: "Analyzing deploy-pipeline/src/deploy.ts...", from: "agent"),
      FeedMessage(
        type: .status, content: "Found 3 timeout handling locations", from: "agent"),
      FeedMessage(
        type: .fileChanged, content: "Modified: src/deploy.ts (+42 -8)", from: "agent"),
      FeedMessage(
        type: .output,
        content: "Adding exponential backoff with jitter to retry logic...", from: "agent"),
    ]
    session.tokensUsed = 28_400
    session.tokenLimit = 100_000
    manager.activeSession = session

    return manager
  }
}
