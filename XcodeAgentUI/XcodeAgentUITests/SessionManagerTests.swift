@testable import Dependencies
import XCTest

@testable import XcodeAgentUI

@MainActor
final class SessionManagerTests: XCTestCase {

  var sut: SessionManager!
  var mockWS: BridgeWebSocket!

  override func setUp() {
    super.setUp()
    mockWS = BridgeWebSocket()
    sut = withDependencies {
      $0.hapticClient = HapticClient(perform: {})
    } operation: {
      SessionManager(bridgeWS: mockWS)
    }
  }

  override func tearDown() {
    sut.endSession()
    mockWS = nil
    sut = nil
    super.tearDown()
  }

  // MARK: - Session Lifecycle

  func testStartSessionCreatesActiveSession() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    XCTAssertNotNil(sut.activeSession)
    XCTAssertEqual(sut.activeSession?.ticketID, "TEST-1")
    XCTAssertEqual(sut.activeSession?.project, "my-project")
    XCTAssertTrue(sut.activeSession?.isActive ?? false)
  }

  func testStartSessionAddsFeedMessage() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    XCTAssertEqual(sut.activeSession?.feedMessages.count, 1)
    XCTAssertEqual(sut.activeSession?.feedMessages.first?.type, .system)
    XCTAssertTrue(
      sut.activeSession?.feedMessages.first?.content.contains("TEST-1") ?? false
    )
  }

  func testStartSessionWithCriteria() {
    sut.startSession(
      ticketID: "TEST-1", project: "my-project",
      criteria: ["Fix the bug", "Add tests", "Update docs"]
    )
    XCTAssertEqual(sut.activeSession?.criteria.count, 3)
    XCTAssertEqual(sut.activeSession?.criteria[0].text, "Fix the bug")
    XCTAssertFalse(sut.activeSession?.criteria[0].isCompleted ?? true)
  }

  func testEndSessionClearsState() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    sut.endSession()
    XCTAssertNil(sut.activeSession)
  }

  func testEndSessionDeactivatesSession() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let session = sut.activeSession
    sut.endSession()
    XCTAssertFalse(session?.isActive ?? true)
  }

  // MARK: - Session State

  func testSessionTokenUsage() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    sut.activeSession?.tokensUsed = 50_000
    sut.activeSession?.tokenLimit = 100_000
    XCTAssertEqual(sut.activeSession?.tokenUsagePercent, 50)
  }

  func testSessionTokenUsageZeroLimit() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    sut.activeSession?.tokensUsed = 1000
    sut.activeSession?.tokenLimit = 0
    XCTAssertEqual(sut.activeSession?.tokenUsagePercent, 0)
  }

  // MARK: - Commands

  func testSendCommandAddsFeedMessage() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    sut.sendCommand("check status")
    XCTAssertEqual(sut.activeSession?.feedMessages.count, 2)
    XCTAssertEqual(sut.activeSession?.feedMessages.last?.type, .humanCommand)
    XCTAssertEqual(sut.activeSession?.feedMessages.last?.content, "check status")
  }

  func testSendCommandWithNoSessionIsNoop() {
    sut.sendCommand("check status")
    XCTAssertNil(sut.activeSession)
  }

  // MARK: - Approval Flow

  func testApproveRequestClearsPending() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let request = ApprovalRequest(description: "Push to main?", messageID: "msg-1")
    sut.activeSession?.pendingApproval = request
    sut.approveRequest(request)
    XCTAssertNil(sut.activeSession?.pendingApproval)
  }

  func testApproveRequestAddsFeedMessage() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let request = ApprovalRequest(description: "Push to main?", messageID: "msg-1")
    sut.activeSession?.pendingApproval = request
    sut.approveRequest(request)
    let lastMessage = sut.activeSession?.feedMessages.last
    XCTAssertEqual(lastMessage?.type, .system)
    XCTAssertTrue(lastMessage?.content.contains("Approved") ?? false)
  }

  func testDenyRequestClearsPending() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let request = ApprovalRequest(description: "Delete branch?", messageID: "msg-2")
    sut.activeSession?.pendingApproval = request
    sut.denyRequest(request)
    XCTAssertNil(sut.activeSession?.pendingApproval)
  }

  func testDenyRequestAddsFeedMessage() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let request = ApprovalRequest(description: "Delete branch?", messageID: "msg-2")
    sut.activeSession?.pendingApproval = request
    sut.denyRequest(request)
    let lastMessage = sut.activeSession?.feedMessages.last
    XCTAssertTrue(lastMessage?.content.contains("Denied") ?? false)
  }

  // MARK: - Diff Management

  func testAddDiffChunk() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let chunk = DiffChunk(
      filePath: "src/main.swift",
      hunks: [
        DiffHunk(
          header: "@@ -1,3 +1,5 @@",
          lines: [
            DiffLine(type: .context, content: "import Foundation", lineNumber: 1),
            DiffLine(type: .addition, content: "import SwiftUI", lineNumber: 2),
          ]
        ),
      ]
    )
    sut.activeSession?.addDiff(chunk)
    XCTAssertEqual(sut.activeSession?.diffChunks.count, 1)
    XCTAssertEqual(sut.activeSession?.diffChunks.first?.filePath, "src/main.swift")
  }

  // MARK: - Criteria Management

  func testUpdateCriteria() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let criteria = [
      AcceptanceCriterion(text: "Write tests"),
      AcceptanceCriterion(text: "Fix bug"),
    ]
    sut.activeSession?.updateCriteria(criteria)
    XCTAssertEqual(sut.activeSession?.criteria.count, 2)
  }

  func testMarkCriterionCompleted() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let criteria = [AcceptanceCriterion(text: "Write tests")]
    sut.activeSession?.updateCriteria(criteria)
    let criterionID = sut.activeSession!.criteria[0].id
    sut.activeSession?.markCriterion(id: criterionID, completed: true)
    XCTAssertTrue(sut.activeSession?.criteria[0].isCompleted ?? false)
  }

  func testMarkCriterionIncomplete() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    let criteria = [AcceptanceCriterion(text: "Write tests", isCompleted: true)]
    sut.activeSession?.updateCriteria(criteria)
    let criterionID = sut.activeSession!.criteria[0].id
    sut.activeSession?.markCriterion(id: criterionID, completed: false)
    XCTAssertFalse(sut.activeSession?.criteria[0].isCompleted ?? true)
  }

  // MARK: - Feed Message Limits

  func testFeedMessageLimit() {
    sut.startSession(ticketID: "TEST-1", project: "my-project")
    for i in 0..<520 {
      sut.activeSession?.addFeedMessage(
        FeedMessage(type: .output, content: "Message \(i)", from: "agent")
      )
    }
    XCTAssertLessThan(sut.activeSession?.feedMessages.count ?? 9999, 600)
  }

  // MARK: - AgentSession Identity

  func testSessionHasUniqueID() {
    let session1 = AgentSession(ticketID: "T-1", project: "p")
    let session2 = AgentSession(ticketID: "T-2", project: "p")
    XCTAssertNotEqual(session1.id, session2.id)
  }

  func testSessionStartedAtIsSet() {
    let before = Date()
    let session = AgentSession(ticketID: "T-1", project: "p")
    let after = Date()
    XCTAssertGreaterThanOrEqual(session.startedAt, before)
    XCTAssertLessThanOrEqual(session.startedAt, after)
  }

  // MARK: - Supporting Types

  func testDiffLineTypes() {
    let addition = DiffLine(type: .addition, content: "new code", lineNumber: 10)
    let deletion = DiffLine(type: .deletion, content: "old code", lineNumber: nil)
    let context = DiffLine(type: .context, content: "unchanged", lineNumber: 5)

    XCTAssertEqual(addition.type, .addition)
    XCTAssertEqual(deletion.type, .deletion)
    XCTAssertEqual(context.type, .context)
  }

  func testApprovalRequestIdentity() {
    let r1 = ApprovalRequest(description: "test1")
    let r2 = ApprovalRequest(description: "test2")
    XCTAssertNotEqual(r1.id, r2.id)
  }

  func testFeedMessageTypes() {
    let types: [FeedMessage.FeedMessageType] = [
      .output, .error, .status, .fileChanged, .approval, .humanCommand, .system,
    ]
    XCTAssertEqual(types.count, 7)
  }

  // MARK: - Mock Session Manager

  func testMockSessionManagerHasSession() {
    let mock = MockSessionManager.create()
    XCTAssertNotNil(mock.activeSession)
    XCTAssertEqual(mock.activeSession?.ticketID, "INFRA-1024")
    XCTAssertFalse(mock.activeSession?.feedMessages.isEmpty ?? true)
    XCTAssertFalse(mock.activeSession?.criteria.isEmpty ?? true)
  }
}
