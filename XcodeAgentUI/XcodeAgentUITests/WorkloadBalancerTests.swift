import XCTest

@testable import XcodeAgentUI

@MainActor
final class WorkloadBalancerTests: XCTestCase {

  var sut: WorkloadBalancer!

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: "workloadBalancer.agents")
    UserDefaults.standard.removeObject(forKey: "workloadBalancer.unassignedTickets")
    sut = WorkloadBalancer()
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "workloadBalancer.agents")
    UserDefaults.standard.removeObject(forKey: "workloadBalancer.unassignedTickets")
    sut = nil
    super.tearDown()
  }

  // MARK: - Agent Management

  func testDefaultAgentsSeeded() {
    XCTAssertEqual(sut.agents.count, 3)
    XCTAssertEqual(sut.agents[0].model, .opus)
    XCTAssertEqual(sut.agents[1].model, .sonnet)
  }

  func testAddAgent() {
    sut.addAgent(name: "Agent-4", model: .opus)
    XCTAssertEqual(sut.agents.count, 4)
    XCTAssertEqual(sut.agents.last?.name, "Agent-4")
    XCTAssertEqual(sut.agents.last?.model, .opus)
  }

  func testRemoveAgent() {
    let agent = sut.agents[0]
    sut.removeAgent(agent)
    XCTAssertEqual(sut.agents.count, 2)
    XCTAssertFalse(sut.agents.contains(where: { $0.id == agent.id }))
  }

  func testRemoveAgentMovesTicketsToUnassigned() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: agent)
    XCTAssertTrue(sut.unassignedTickets.isEmpty)

    sut.removeAgent(agent)
    XCTAssertEqual(sut.unassignedTickets.count, 1)
    XCTAssertEqual(sut.unassignedTickets.first?.ticketID, "T-1")
  }

  func testToggleAgentState() {
    let agent = sut.agents[0]
    XCTAssertEqual(agent.state, .idle)

    sut.toggleAgentState(agent)
    XCTAssertEqual(sut.agents[0].state, .paused)

    sut.toggleAgentState(agent)
    XCTAssertEqual(sut.agents[0].state, .idle)
  }

  func testToggleAgentStateFromWorking() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: agent)
    XCTAssertEqual(sut.agents[0].state, .working)

    sut.toggleAgentState(agent)
    XCTAssertEqual(sut.agents[0].state, .paused)
  }

  func testToggleAgentStateFromOffline() {
    let agent = sut.agents[0]
    sut.setAgentOffline(agent)
    XCTAssertEqual(sut.agents[0].state, .offline)

    sut.toggleAgentState(agent)
    XCTAssertEqual(sut.agents[0].state, .idle)
  }

  func testSetAgentOffline() {
    let agent = sut.agents[0]
    sut.setAgentOffline(agent)
    XCTAssertEqual(sut.agents[0].state, .offline)
  }

  // MARK: - Ticket Management

  func testAddTicket() {
    let ticket = makeTicket("T-1")
    sut.addTicket(ticket)
    XCTAssertEqual(sut.unassignedTickets.count, 1)
    XCTAssertEqual(sut.unassignedTickets.first?.ticketID, "T-1")
  }

  func testRemoveTicketFromUnassigned() {
    let ticket = makeTicket("T-1")
    sut.addTicket(ticket)
    sut.removeTicket(ticket)
    XCTAssertTrue(sut.unassignedTickets.isEmpty)
  }

  func testRemoveTicketFromAgent() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: agent)
    XCTAssertEqual(sut.agents[0].ticketCount, 1)

    sut.removeTicket(ticket)
    XCTAssertEqual(sut.agents[0].ticketCount, 0)
  }

  // MARK: - Assignment

  func testAssignTicket() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.addTicket(ticket)
    sut.assignTicket(ticket, to: agent)

    XCTAssertTrue(sut.unassignedTickets.isEmpty)
    XCTAssertEqual(sut.agents[0].ticketCount, 1)
    XCTAssertEqual(sut.agents[0].state, .working)
  }

  func testAssignTicketSetsAgentID() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: agent)
    XCTAssertEqual(sut.agents[0].assignedTickets.first?.assignedAgentID, agent.id)
  }

  func testUnassignTicket() {
    let agent = sut.agents[0]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: agent)
    sut.unassignTicket(ticket, from: agent)

    XCTAssertEqual(sut.agents[0].ticketCount, 0)
    XCTAssertEqual(sut.agents[0].state, .idle)
    XCTAssertEqual(sut.unassignedTickets.count, 1)
  }

  func testMoveTicketBetweenAgents() {
    let source = sut.agents[0]
    let target = sut.agents[1]
    let ticket = makeTicket("T-1")
    sut.assignTicket(ticket, to: source)

    sut.moveTicket(ticket, from: source, to: target)

    XCTAssertEqual(sut.agents[0].ticketCount, 0)
    XCTAssertEqual(sut.agents[0].state, .idle)
    XCTAssertEqual(sut.agents[1].ticketCount, 1)
    XCTAssertEqual(sut.agents[1].state, .working)
  }

  // MARK: - Auto-Balance

  func testAutoBalance() {
    sut.addTicket(makeTicket("T-1"))
    sut.addTicket(makeTicket("T-2"))
    sut.addTicket(makeTicket("T-3"))

    sut.autoBalance()

    XCTAssertTrue(sut.unassignedTickets.isEmpty)
    let totalAssigned = sut.agents.reduce(0) { $0 + $1.ticketCount }
    XCTAssertEqual(totalAssigned, 3)
  }

  func testAutoAssignSingle() {
    let ticket = makeTicket("T-1")
    sut.addTicket(ticket)
    sut.autoAssignSingle(ticket)

    XCTAssertTrue(sut.unassignedTickets.isEmpty)
    let totalAssigned = sut.agents.reduce(0) { $0 + $1.ticketCount }
    XCTAssertEqual(totalAssigned, 1)
  }

  func testAutoAssignSingleNoAvailableAgents() {
    for agent in sut.agents {
      sut.setAgentOffline(agent)
    }
    let ticket = makeTicket("T-1")
    sut.addTicket(ticket)
    sut.autoAssignSingle(ticket)

    XCTAssertEqual(sut.unassignedTickets.count, 1)
  }

  func testRebalanceAll() {
    let agent = sut.agents[0]
    sut.assignTicket(makeTicket("T-1"), to: agent)
    sut.assignTicket(makeTicket("T-2"), to: agent)
    sut.assignTicket(makeTicket("T-3"), to: agent)

    sut.rebalanceAll()

    let totalAssigned = sut.agents.reduce(0) { $0 + $1.ticketCount }
    XCTAssertEqual(totalAssigned, 3)
    XCTAssertLessThanOrEqual(sut.agents[0].ticketCount, 2)
  }

  func testRebalanceAllNoAvailableAgents() {
    sut.addTicket(makeTicket("T-1"))
    for agent in sut.agents {
      sut.setAgentOffline(agent)
    }

    sut.rebalanceAll()

    XCTAssertEqual(sut.unassignedTickets.count, 1)
  }

  // MARK: - Scheduling

  func testScheduleAgent() {
    let agent = sut.agents[0]
    let schedule = AgentSchedule(
      startTime: Date(),
      endTime: Date().addingTimeInterval(3600),
      label: "Test"
    )
    sut.scheduleAgent(agent, schedule: schedule)

    XCTAssertEqual(sut.agents[0].state, .scheduled)
    XCTAssertNotNil(sut.agents[0].schedule)
  }

  func testClearSchedule() {
    let agent = sut.agents[0]
    let schedule = AgentSchedule(
      startTime: Date(),
      endTime: Date().addingTimeInterval(3600),
      label: "Test"
    )
    sut.scheduleAgent(agent, schedule: schedule)
    sut.clearSchedule(agent)

    XCTAssertNil(sut.agents[0].schedule)
    XCTAssertEqual(sut.agents[0].state, .idle)
  }

  func testClearScheduleWithTicketsTransitionsToWorking() {
    let agent = sut.agents[0]
    sut.assignTicket(makeTicket("T-1"), to: agent)

    let schedule = AgentSchedule(
      startTime: Date(),
      endTime: Date().addingTimeInterval(3600),
      label: "Test"
    )
    sut.scheduleAgent(agent, schedule: schedule)
    sut.clearSchedule(agent)

    XCTAssertEqual(sut.agents[0].state, .working)
  }

  // MARK: - Stats

  func testTotalTickets() {
    sut.addTicket(makeTicket("T-1"))
    sut.addTicket(makeTicket("T-2"))
    sut.assignTicket(makeTicket("T-3"), to: sut.agents[0])

    XCTAssertEqual(sut.totalTickets, 3)
  }

  func testAverageLoad() {
    XCTAssertEqual(sut.averageLoad, 0.0)

    sut.assignTicket(makeTicket("T-1"), to: sut.agents[0])
    XCTAssertGreaterThan(sut.averageLoad, 0.0)
  }

  func testActiveAgentCount() {
    XCTAssertEqual(sut.activeAgentCount, 0)

    sut.assignTicket(makeTicket("T-1"), to: sut.agents[0])
    XCTAssertEqual(sut.activeAgentCount, 1)
  }

  // MARK: - Balancing Strategy

  func testPriorityWeightedPrefersOpusForCritical() {
    sut.balancingStrategy = .priorityWeighted
    let criticalTicket = makeTicket("T-1", priority: .critical)
    sut.addTicket(criticalTicket)
    sut.autoAssignSingle(criticalTicket)

    XCTAssertEqual(sut.agents[0].ticketCount, 1)
  }

  // MARK: - Helpers

  private func makeTicket(
    _ id: String,
    priority: TicketPriority = .medium
  ) -> WorkloadTicket {
    WorkloadTicket(
      ticketID: id,
      title: "Test ticket \(id)",
      project: "test-project",
      priority: priority
    )
  }
}
