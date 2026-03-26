import XCTest

@testable import XcodeAgentUI

final class QueueManagerTests: XCTestCase {

  var sut: QueueManager!

  override func setUp() {
    super.setUp()
    // Clear persisted state for clean tests
    UserDefaults.standard.removeObject(forKey: "queueTickets")
    UserDefaults.standard.removeObject(forKey: "queueConcurrencyLimits")
    UserDefaults.standard.removeObject(forKey: "queueAutoAssignRules")
    UserDefaults.standard.removeObject(forKey: "queueAutoAssign")
    sut = QueueManager()
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "queueTickets")
    UserDefaults.standard.removeObject(forKey: "queueConcurrencyLimits")
    UserDefaults.standard.removeObject(forKey: "queueAutoAssignRules")
    UserDefaults.standard.removeObject(forKey: "queueAutoAssign")
    sut = nil
    super.tearDown()
  }

  // MARK: - Adding Tickets

  func testAddTicketIncreasesCount() {
    let ticket = makeTicket("TEST-1")
    sut.addTicket(ticket)
    XCTAssertEqual(sut.tickets.count, 1)
  }

  func testAddMultipleTickets() {
    sut.addTicket(makeTicket("TEST-1"))
    sut.addTicket(makeTicket("TEST-2"))
    sut.addTicket(makeTicket("TEST-3"))
    XCTAssertEqual(sut.tickets.count, 3)
  }

  func testAddTicketDefaultsPending() {
    let ticket = makeTicket("TEST-1")
    sut.addTicket(ticket)
    XCTAssertEqual(sut.tickets.first?.status, .pending)
  }

  // MARK: - Removing Tickets

  func testRemoveTicket() {
    let ticket = makeTicket("TEST-1")
    sut.addTicket(ticket)
    let id = sut.tickets.first!.id
    sut.removeTicket(id: id)
    XCTAssertTrue(sut.tickets.isEmpty)
  }

  func testRemoveNonexistentTicketIsNoop() {
    sut.addTicket(makeTicket("TEST-1"))
    sut.removeTicket(id: UUID())
    XCTAssertEqual(sut.tickets.count, 1)
  }

  // MARK: - Priority Ordering

  func testHighPriorityInsertedBeforeLow() {
    sut.addTicket(makeTicket("LOW-1", priority: .low))
    sut.addTicket(makeTicket("HIGH-1", priority: .high))
    // High priority should come before low
    XCTAssertEqual(sut.tickets.first?.ticketID, "HIGH-1")
  }

  func testCriticalPriorityInsertedFirst() {
    sut.addTicket(makeTicket("MED-1", priority: .medium))
    sut.addTicket(makeTicket("LOW-1", priority: .low))
    sut.addTicket(makeTicket("CRIT-1", priority: .critical))
    XCTAssertEqual(sut.tickets.first?.ticketID, "CRIT-1")
  }

  func testUpdatePriority() {
    sut.addTicket(makeTicket("TEST-1", priority: .low))
    let id = sut.tickets.first!.id
    sut.updatePriority(id: id, priority: .critical)
    XCTAssertEqual(sut.tickets.first?.priority, .critical)
  }

  // MARK: - Reordering

  func testMoveTicket() {
    sut.addTicket(makeTicket("A"))
    sut.addTicket(makeTicket("B"))
    sut.addTicket(makeTicket("C"))
    // Move first item to end
    sut.moveTicket(from: IndexSet(integer: 0), to: 3)
    XCTAssertEqual(sut.tickets.last?.ticketID, "A")
  }

  func testReorderTicketById() {
    sut.addTicket(makeTicket("A"))
    sut.addTicket(makeTicket("B"))
    sut.addTicket(makeTicket("C"))
    let idA = sut.tickets.first(where: { $0.ticketID == "A" })!.id
    sut.reorderTicket(id: idA, to: 2)
    XCTAssertEqual(sut.tickets[2].ticketID, "A")
  }

  // MARK: - Status Transitions

  func testPauseRunningTicket() {
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 5, maxOpus: 5)
    sut.addTicket(makeTicket("TEST-1"))  // Will auto-dispatch since limits are high
    let id = sut.tickets.first!.id

    // If it got dispatched to running, pause it
    if sut.tickets.first?.status == .running {
      sut.pauseTicket(id: id)
      XCTAssertEqual(sut.tickets.first?.status, .paused)
    }
  }

  func testPausePendingTicketIsNoop() {
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 0, maxOpus: 0)
    sut.addTicket(makeTicket("TEST-1"))
    let id = sut.tickets.first!.id
    sut.pauseTicket(id: id)
    // Should still be pending since it wasn't running
    XCTAssertEqual(sut.tickets.first?.status, .pending)
  }

  func testMarkCompleted() {
    sut.addTicket(makeTicket("TEST-1"))
    let id = sut.tickets.first!.id
    sut.markCompleted(id: id)
    XCTAssertEqual(sut.tickets.first?.status, .completed)
  }

  func testMarkFailed() {
    sut.addTicket(makeTicket("TEST-1"))
    let id = sut.tickets.first!.id
    sut.markFailed(id: id)
    XCTAssertEqual(sut.tickets.first?.status, .failed)
  }

  // MARK: - Concurrency Limits

  func testConcurrencyLimitsDefault() {
    XCTAssertEqual(sut.concurrencyLimits.maxSonnet, 2)
    XCTAssertEqual(sut.concurrencyLimits.maxOpus, 1)
  }

  func testConcurrencyLimitsEnforced() {
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 1, maxOpus: 0)
    sut.addTicket(makeTicket("S1", model: "Sonnet"))
    sut.addTicket(makeTicket("S2", model: "Sonnet"))
    sut.addTicket(makeTicket("S3", model: "Sonnet"))

    let running = sut.tickets.filter { $0.status == .running }
    XCTAssertLessThanOrEqual(running.count, 1)
  }

  func testOpusConcurrencyRespected() {
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 0, maxOpus: 1)
    sut.addTicket(makeTicket("O1", model: "Opus"))
    sut.addTicket(makeTicket("O2", model: "Opus"))

    let runningOpus = sut.tickets.filter { $0.status == .running && $0.model == "Opus" }
    XCTAssertLessThanOrEqual(runningOpus.count, 1)
  }

  // MARK: - Auto-Assignment Rules

  func testAutoAssignRuleMatchesTag() {
    sut.isAutoAssignEnabled = true
    sut.addRule(AutoAssignRule(pattern: "infra", assignModel: "Opus"))

    var ticket = makeTicket("INFRA-1", model: "Sonnet")
    ticket.tags = ["infra", "deploy"]
    sut.addTicket(ticket)

    // The ticket should have been auto-assigned to Opus
    XCTAssertEqual(sut.tickets.first?.model, "Opus")
  }

  func testAutoAssignRuleMatchesTicketID() {
    sut.isAutoAssignEnabled = true
    sut.addRule(AutoAssignRule(pattern: "mobile", assignModel: "Opus"))
    sut.addTicket(makeTicket("MOBILE-100", model: "Sonnet"))
    XCTAssertEqual(sut.tickets.first?.model, "Opus")
  }

  func testAutoAssignDisabled() {
    sut.isAutoAssignEnabled = false
    sut.addRule(AutoAssignRule(pattern: "infra", assignModel: "Opus"))

    var ticket = makeTicket("INFRA-1", model: "Sonnet")
    ticket.tags = ["infra"]
    sut.addTicket(ticket)

    // Should keep original model when auto-assign is off
    XCTAssertEqual(sut.tickets.first?.model, "Sonnet")
  }

  func testRemoveRule() {
    let rule = AutoAssignRule(pattern: "test", assignModel: "Opus")
    sut.addRule(rule)
    XCTAssertEqual(sut.autoAssignRules.count, 1)
    sut.removeRule(id: rule.id)
    XCTAssertTrue(sut.autoAssignRules.isEmpty)
  }

  // MARK: - Computed Properties

  func testPendingCount() {
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 0, maxOpus: 0)
    sut.addTicket(makeTicket("A"))
    sut.addTicket(makeTicket("B"))
    XCTAssertEqual(sut.pendingCount, 2)
  }

  func testCompletedCount() {
    sut.addTicket(makeTicket("A"))
    sut.addTicket(makeTicket("B"))
    sut.markCompleted(id: sut.tickets[0].id)
    sut.markFailed(id: sut.tickets[1].id)
    XCTAssertEqual(sut.completedCount, 2)
  }

  // MARK: - Clear Completed

  func testClearCompleted() {
    sut.addTicket(makeTicket("A"))
    sut.addTicket(makeTicket("B"))
    sut.addTicket(makeTicket("C"))
    sut.markCompleted(id: sut.tickets[0].id)
    sut.markFailed(id: sut.tickets[1].id)
    sut.clearCompleted()
    XCTAssertEqual(sut.tickets.count, 1)
    XCTAssertEqual(sut.tickets.first?.ticketID, "C")
  }

  // MARK: - Dispatch Callback

  func testDispatchCallbackFires() {
    let expectation = expectation(description: "dispatch")
    sut.concurrencyLimits = ConcurrencyLimits(maxSonnet: 1, maxOpus: 1)
    sut.onDispatch = { ticket in
      XCTAssertEqual(ticket.ticketID, "DISPATCH-1")
      expectation.fulfill()
    }
    sut.addTicket(makeTicket("DISPATCH-1"))
    waitForExpectations(timeout: 1)
  }

  // MARK: - Mock Data

  func testMockTicketDataIsValid() {
    let tickets = MockTicketData.sampleQueueTickets
    XCTAssertFalse(tickets.isEmpty)
    XCTAssertTrue(tickets.allSatisfy { !$0.ticketID.isEmpty })
    XCTAssertTrue(tickets.allSatisfy { !$0.project.isEmpty })
  }

  func testMockCriteriaIsValid() {
    let criteria = MockTicketData.sampleCriteria
    XCTAssertFalse(criteria.isEmpty)
    XCTAssertTrue(criteria.allSatisfy { !$0.text.isEmpty })
  }

  func testMockFeedMessagesAreChronological() {
    let messages = MockTicketData.sampleFeedMessages
    for i in 1..<messages.count {
      XCTAssertGreaterThanOrEqual(
        messages[i].timestamp.timeIntervalSince1970,
        messages[i - 1].timestamp.timeIntervalSince1970
      )
    }
  }

  // MARK: - Helpers

  private func makeTicket(
    _ id: String,
    model: String = "Sonnet",
    priority: QueueTicket.Priority = .medium
  ) -> QueueTicket {
    QueueTicket(
      ticketID: id,
      project: "test-project",
      providerType: "github",
      model: model,
      priority: priority
    )
  }
}
