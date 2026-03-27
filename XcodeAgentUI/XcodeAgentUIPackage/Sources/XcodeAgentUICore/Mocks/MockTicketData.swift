import Foundation

// MARK: - Mock Ticket Data

/// Central repository of sample data for previews, tests, and demo mode.
/// All data is realistic and internally consistent.
public enum MockTicketData {

  // MARK: - Queue Tickets

  static let sampleQueueTickets: [QueueTicket] = [
    QueueTicket(
      ticketID: "MOBILE-2847",
      project: "ios-shopping-app",
      providerType: "github",
      model: "Opus",
      priority: .critical,
      tags: ["bug", "checkout", "p0"]
    ),
    QueueTicket(
      ticketID: "MOBILE-2851",
      project: "ios-shopping-app",
      providerType: "github",
      model: "Sonnet",
      priority: .high,
      tags: ["feature", "search"]
    ),
    QueueTicket(
      ticketID: "INFRA-1024",
      project: "deploy-pipeline",
      providerType: "github",
      model: "Sonnet",
      priority: .high,
      tags: ["infra", "retry"]
    ),
    QueueTicket(
      ticketID: "WEB-445",
      project: "marketing-site",
      providerType: "github",
      model: "Sonnet",
      priority: .medium,
      tags: ["frontend", "responsive"]
    ),
    QueueTicket(
      ticketID: "API-312",
      project: "rest-api-v3",
      providerType: "jira",
      model: "Opus",
      priority: .medium,
      tags: ["api", "pagination"]
    ),
    QueueTicket(
      ticketID: "DOCS-89",
      project: "developer-docs",
      providerType: "github",
      model: "Sonnet",
      priority: .low,
      tags: ["docs", "api-reference"]
    ),
  ]

  // MARK: - Acceptance Criteria

  static let sampleCriteria: [AcceptanceCriterion] = [
    AcceptanceCriterion(text: "Fix checkout crash on nil address", isCompleted: true),
    AcceptanceCriterion(text: "Add input validation for postal codes", isCompleted: true),
    AcceptanceCriterion(text: "Update snapshot tests"),
    AcceptanceCriterion(text: "Handle edge case: empty cart at checkout"),
  ]

  // MARK: - Feed Messages

  static let sampleFeedMessages: [FeedMessage] = [
    FeedMessage(
      type: .system,
      content: "Session started for MOBILE-2847",
      from: "system",
      timestamp: Date().addingTimeInterval(-300)
    ),
    FeedMessage(
      type: .output,
      content: "Cloning ios-shopping-app and checking out branch fix/checkout-crash...",
      from: "agent",
      timestamp: Date().addingTimeInterval(-290)
    ),
    FeedMessage(
      type: .output,
      content: "Analyzing CheckoutViewController.swift — found nil dereference on line 142",
      from: "agent",
      timestamp: Date().addingTimeInterval(-240)
    ),
    FeedMessage(
      type: .fileChanged,
      content: "Modified: Sources/Checkout/CheckoutViewController.swift (+18 -3)",
      from: "agent",
      timestamp: Date().addingTimeInterval(-200)
    ),
    FeedMessage(
      type: .status,
      content: "Build succeeded — running test suite...",
      from: "agent",
      timestamp: Date().addingTimeInterval(-150)
    ),
    FeedMessage(
      type: .output,
      content: "14/14 tests passed. Adding postal code validation...",
      from: "agent",
      timestamp: Date().addingTimeInterval(-120)
    ),
    FeedMessage(
      type: .fileChanged,
      content: "Modified: Sources/Checkout/AddressValidator.swift (+45 -0)",
      from: "agent",
      timestamp: Date().addingTimeInterval(-80)
    ),
    FeedMessage(
      type: .approval,
      content: "Ready to push changes to fix/checkout-crash. Approve?",
      from: "agent",
      timestamp: Date().addingTimeInterval(-30)
    ),
  ]

  // MARK: - Diff Chunks

  static let sampleDiffChunks: [DiffChunk] = [
    DiffChunk(
      filePath: "Sources/Checkout/CheckoutViewController.swift",
      hunks: [
        DiffHunk(
          header: "@@ -140,6 +140,21 @@",
          lines: [
            DiffLine(type: .context, content: "    func processCheckout() {", lineNumber: 140),
            DiffLine(
              type: .deletion, content: "        let address = user.address!", lineNumber: nil),
            DiffLine(
              type: .addition, content: "        guard let address = user.address else {",
              lineNumber: 141),
            DiffLine(
              type: .addition,
              content: "            showError(\"Please add a shipping address\")", lineNumber: 142),
            DiffLine(type: .addition, content: "            return", lineNumber: 143),
            DiffLine(type: .addition, content: "        }", lineNumber: 144),
            DiffLine(type: .context, content: "        let cart = CartManager.shared.items",
              lineNumber: 145),
          ]
        ),
      ]
    ),
    DiffChunk(
      filePath: "Sources/Checkout/AddressValidator.swift",
      hunks: [
        DiffHunk(
          header: "@@ -0,0 +1,25 @@",
          lines: [
            DiffLine(
              type: .addition, content: "struct AddressValidator {", lineNumber: 1),
            DiffLine(
              type: .addition, content: "    static func validate(_ address: Address) -> Bool {",
              lineNumber: 2),
            DiffLine(
              type: .addition,
              content: "        guard !address.postalCode.isEmpty else { return false }",
              lineNumber: 3),
            DiffLine(
              type: .addition,
              content: "        return postalCodePattern.matches(address.postalCode)",
              lineNumber: 4),
            DiffLine(type: .addition, content: "    }", lineNumber: 5),
            DiffLine(type: .addition, content: "}", lineNumber: 6),
          ]
        ),
      ]
    ),
  ]

  // MARK: - Performance Metrics

  static let sampleTicketRuns: [TicketRun] = [
    TicketRun(
      id: UUID().uuidString, ticketID: "MOBILE-2801", project: "ios-shopping-app", agentModel: "Opus",
      startedAt: Date().addingTimeInterval(-86400 * 3), finishedAt: Date().addingTimeInterval(-86400 * 3 + 480),
      outcome: .success, buildSucceeded: true, testsSucceeded: true, retryCount: 0,
      inputTokens: 40_000, outputTokens: 12_000
    ),
    TicketRun(
      id: UUID().uuidString, ticketID: "MOBILE-2810", project: "ios-shopping-app", agentModel: "Sonnet",
      startedAt: Date().addingTimeInterval(-86400 * 2), finishedAt: Date().addingTimeInterval(-86400 * 2 + 320),
      outcome: .success, buildSucceeded: true, testsSucceeded: true, retryCount: 0,
      inputTokens: 20_000, outputTokens: 8_000
    ),
    TicketRun(
      id: UUID().uuidString, ticketID: "WEB-438", project: "marketing-site", agentModel: "Sonnet",
      startedAt: Date().addingTimeInterval(-86400 * 2), finishedAt: Date().addingTimeInterval(-86400 * 2 + 190),
      outcome: .success, buildSucceeded: true, testsSucceeded: true, retryCount: 0,
      inputTokens: 10_000, outputTokens: 5_000
    ),
    TicketRun(
      id: UUID().uuidString, ticketID: "API-305", project: "rest-api-v3", agentModel: "Opus",
      startedAt: Date().addingTimeInterval(-86400), finishedAt: Date().addingTimeInterval(-86400 + 620),
      outcome: .failure, buildSucceeded: false, testsSucceeded: false, retryCount: 2,
      inputTokens: 50_000, outputTokens: 18_000
    ),
    TicketRun(
      id: UUID().uuidString, ticketID: "MOBILE-2840", project: "ios-shopping-app", agentModel: "Sonnet",
      startedAt: Date().addingTimeInterval(-43200), finishedAt: Date().addingTimeInterval(-43200 + 250),
      outcome: .success, buildSucceeded: true, testsSucceeded: true, retryCount: 0,
      inputTokens: 15_000, outputTokens: 7_000
    ),
  ]

  // MARK: - Workload Agents

  static let sampleWorkerNames: [String] = [
    "agent:sonnet-1",
    "agent:sonnet-2",
    "agent:opus-1",
  ]
}
