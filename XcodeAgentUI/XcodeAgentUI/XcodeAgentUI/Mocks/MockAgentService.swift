import Combine
import Foundation

// MARK: - Mock Agent Service

/// Fully populated AgentService for SwiftUI previews and tests.
/// Pre-loads sample data across all sub-managers so every view has content to render.
class MockAgentService: AgentService {

  static let shared = MockAgentService()

  override init() {
    super.init()
    seedAllMockData()
  }

  private func seedAllMockData() {
    // Simulate running services
    routerStatus = ServiceStatus(id: "router", name: "Router", state: .running, port: 3800)
    bridgeStatus = ServiceStatus(id: "bridge", name: "Bridge", state: .running, port: 9300)
    workerCount = 3

    // Seed an active session
    let session = AgentSession(ticketID: "MOBILE-2847", project: "ios-shopping-app")
    session.criteria = MockTicketData.sampleCriteria
    session.feedMessages = MockTicketData.sampleFeedMessages
    session.diffChunks = MockTicketData.sampleDiffChunks
    session.tokensUsed = 45_200
    session.tokenLimit = 100_000
    sessionManager.activeSession = session

    // Seed queue
    seedQueue()

    // Seed metrics
    metricsStore.seedDemoData()

    // Seed providers
    seedProviders()
  }

  private func seedQueue() {
    let tickets = MockTicketData.sampleQueueTickets
    for ticket in tickets {
      queueManager.addTicket(ticket)
    }
  }

  private func seedProviders() {
    let github = Provider(
      type: .github,
      name: "GitHub – openclaw",
      baseURL: "https://api.github.com",
      defaultProject: "openclaw/xcode-agent"
    )
    providerStore.addProvider(github)

    let jira = Provider(
      type: .jira,
      name: "Jira – Mobile Team",
      baseURL: "https://team.atlassian.net",
      defaultProject: "MOBILE"
    )
    providerStore.addProvider(jira)
  }
}

// MARK: - Mock Session Manager

/// Standalone mock SessionManager for isolated view testing.
class MockSessionManager: SessionManager {

  convenience init() {
    let mockWS = BridgeWebSocket()
    self.init(bridgeWS: mockWS)
    seedSession()
  }

  private func seedSession() {
    let session = AgentSession(ticketID: "INFRA-1024", project: "deploy-pipeline")
    session.criteria = [
      AcceptanceCriterion(text: "Add retry logic to deploy step"),
      AcceptanceCriterion(text: "Handle timeout errors gracefully", isCompleted: true),
      AcceptanceCriterion(text: "Update integration tests"),
    ]
    session.feedMessages = [
      FeedMessage(type: .system, content: "Session started for INFRA-1024", from: "system"),
      FeedMessage(type: .output, content: "Analyzing deploy-pipeline/src/deploy.ts...", from: "agent"),
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
    activeSession = session
  }
}
