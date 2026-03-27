import Foundation
import Observation

@Observable @MainActor
public final class WorkloadBalancer {

  // MARK: - State

  public var agents: [AgentWorker] = []
  public var unassignedTickets: [WorkloadTicket] = []
  public var balancingStrategy: BalancingStrategy = .leastLoaded

  // MARK: - Persistence Keys

  private let agentsKey = "workloadBalancer.agents"
  private let ticketsKey = "workloadBalancer.unassignedTickets"

  // MARK: - Init

  public init() {
    loadPersistedState()
    if agents.isEmpty {
      agents = [
        AgentWorker(name: "Agent-1", model: .opus),
        AgentWorker(name: "Agent-2", model: .sonnet),
        AgentWorker(name: "Agent-3", model: .sonnet),
      ]
    }
  }

  // MARK: - Agent Management

  public func addAgent(name: String, model: AgentModel) {
    let agent = AgentWorker(name: name, model: model)
    agents.append(agent)
    persistState()
  }

  public func removeAgent(_ agent: AgentWorker) {
    for ticket in agent.assignedTickets {
      var t = ticket
      t.assignedAgentID = nil
      unassignedTickets.append(t)
    }
    agents.removeAll { $0.id == agent.id }
    persistState()
  }

  public func toggleAgentState(_ agent: AgentWorker) {
    guard let idx = agents.firstIndex(where: { $0.id == agent.id }) else { return }
    switch agents[idx].state {
    case .idle:
      agents[idx].state = .paused
    case .working:
      agents[idx].state = .paused
    case .paused:
      agents[idx].state = .idle
    case .offline:
      agents[idx].state = .idle
    case .scheduled:
      agents[idx].state = .idle
      agents[idx].schedule = nil
    }
    persistState()
  }

  public func setAgentOffline(_ agent: AgentWorker) {
    guard let idx = agents.firstIndex(where: { $0.id == agent.id }) else { return }
    agents[idx].state = .offline
    persistState()
  }

  // MARK: - Ticket Management

  public func addTicket(_ ticket: WorkloadTicket) {
    unassignedTickets.append(ticket)
    persistState()
  }

  public func removeTicket(_ ticket: WorkloadTicket) {
    unassignedTickets.removeAll { $0.id == ticket.id }
    for agent in agents {
      agent.assignedTickets.removeAll { $0.id == ticket.id }
      agent.recalculateLoad()
    }
    persistState()
  }

  // MARK: - Assignment

  public func assignTicket(_ ticket: WorkloadTicket, to agent: AgentWorker) {
    guard let agentIdx = agents.firstIndex(where: { $0.id == agent.id }) else { return }

    unassignedTickets.removeAll { $0.id == ticket.id }

    for other in agents {
      other.assignedTickets.removeAll { $0.id == ticket.id }
      other.recalculateLoad()
    }

    var t = ticket
    t.assignedAgentID = agent.id
    agents[agentIdx].assignedTickets.append(t)
    agents[agentIdx].recalculateLoad()

    if agents[agentIdx].state == .idle {
      agents[agentIdx].state = .working
    }

    persistState()
  }

  public func unassignTicket(_ ticket: WorkloadTicket, from agent: AgentWorker) {
    guard let agentIdx = agents.firstIndex(where: { $0.id == agent.id }) else { return }
    agents[agentIdx].assignedTickets.removeAll { $0.id == ticket.id }
    agents[agentIdx].recalculateLoad()

    if agents[agentIdx].assignedTickets.isEmpty && agents[agentIdx].state == .working {
      agents[agentIdx].state = .idle
    }

    var t = ticket
    t.assignedAgentID = nil
    unassignedTickets.append(t)

    persistState()
  }

  public func moveTicket(_ ticket: WorkloadTicket, from source: AgentWorker, to target: AgentWorker) {
    guard let srcIdx = agents.firstIndex(where: { $0.id == source.id }),
      let tgtIdx = agents.firstIndex(where: { $0.id == target.id }) else { return }

    agents[srcIdx].assignedTickets.removeAll { $0.id == ticket.id }
    agents[srcIdx].recalculateLoad()

    if agents[srcIdx].assignedTickets.isEmpty && agents[srcIdx].state == .working {
      agents[srcIdx].state = .idle
    }

    var t = ticket
    t.assignedAgentID = target.id
    agents[tgtIdx].assignedTickets.append(t)
    agents[tgtIdx].recalculateLoad()

    if agents[tgtIdx].state == .idle {
      agents[tgtIdx].state = .working
    }

    persistState()
  }

  // MARK: - Auto-Balance

  public func autoBalance() {
    let sorted = unassignedTickets.sorted { $0.priority.sortOrder < $1.priority.sortOrder }

    for ticket in sorted {
      guard let target = leastLoadedAgent() else { break }
      assignTicket(ticket, to: target)
    }
  }

  public func autoAssignSingle(_ ticket: WorkloadTicket) {
    guard let target = bestAgentForTicket(ticket) else { return }
    assignTicket(ticket, to: target)
  }

  public func rebalanceAll() {
    var allTickets: [WorkloadTicket] = unassignedTickets
    for agent in agents {
      allTickets.append(contentsOf: agent.assignedTickets)
      agent.assignedTickets.removeAll()
      agent.recalculateLoad()
      if agent.state == .working { agent.state = .idle }
    }
    unassignedTickets.removeAll()

    allTickets.sort { $0.priority.sortOrder < $1.priority.sortOrder }
    let available = agents.filter { $0.isAvailable }

    guard !available.isEmpty else {
      unassignedTickets = allTickets
      persistState()
      return
    }

    for ticket in allTickets {
      guard let target = leastLoadedAgent() else {
        var t = ticket
        t.assignedAgentID = nil
        unassignedTickets.append(t)
        continue
      }
      assignTicket(ticket, to: target)
    }

    persistState()
  }

  // MARK: - Scheduling

  public func scheduleAgent(_ agent: AgentWorker, schedule: AgentSchedule) {
    guard let idx = agents.firstIndex(where: { $0.id == agent.id }) else { return }
    agents[idx].schedule = schedule
    agents[idx].state = .scheduled
    persistState()
  }

  public func clearSchedule(_ agent: AgentWorker) {
    guard let idx = agents.firstIndex(where: { $0.id == agent.id }) else { return }
    agents[idx].schedule = nil
    if agents[idx].state == .scheduled {
      agents[idx].state = agents[idx].assignedTickets.isEmpty ? .idle : .working
    }
    persistState()
  }

  // MARK: - Load Balancing Algorithm

  private func leastLoadedAgent() -> AgentWorker? {
    agents
      .filter { $0.isAvailable }
      .min { $0.cpuLoad < $1.cpuLoad }
  }

  private func bestAgentForTicket(_ ticket: WorkloadTicket) -> AgentWorker? {
    switch balancingStrategy {
    case .leastLoaded:
      return leastLoadedAgent()
    case .roundRobin:
      return agents
        .filter { $0.isAvailable }
        .min { $0.ticketCount < $1.ticketCount }
    case .priorityWeighted:
      if ticket.priority == .critical || ticket.priority == .high {
        let opus = agents.filter { $0.isAvailable && $0.model == .opus }
          .min { $0.cpuLoad < $1.cpuLoad }
        if let opus = opus { return opus }
      }
      return leastLoadedAgent()
    }
  }

  // MARK: - Stats

  public var totalTickets: Int {
    agents.reduce(0) { $0 + $1.ticketCount } + unassignedTickets.count
  }

  public var averageLoad: Double {
    guard !agents.isEmpty else { return 0 }
    return agents.reduce(0.0) { $0 + $1.cpuLoad } / Double(agents.count)
  }

  public var activeAgentCount: Int {
    agents.filter { $0.state == .working }.count
  }

  // MARK: - Persistence

  private func persistState() {
    let agentData = agents.map { agent -> [String: Any] in
      [
        "id": agent.id.uuidString,
        "name": agent.name,
        "model": agent.model == .opus ? "opus" : "sonnet",
        "state": agent.state.rawValue,
      ]
    }
    UserDefaults.standard.set(agentData, forKey: agentsKey)

    if let encoded = try? JSONEncoder().encode(unassignedTickets) {
      UserDefaults.standard.set(encoded, forKey: ticketsKey)
    }
  }

  private func loadPersistedState() {
    if let agentData = UserDefaults.standard.array(forKey: agentsKey) as? [[String: Any]] {
      agents = agentData.compactMap { dict in
        guard let idStr = dict["id"] as? String,
          let id = UUID(uuidString: idStr),
          let name = dict["name"] as? String,
          let modelStr = dict["model"] as? String,
          let stateStr = dict["state"] as? String else { return nil }
        let model: AgentModel = modelStr == "opus" ? .opus : .sonnet
        let state = AgentWorkerState(rawValue: stateStr) ?? .idle
        return AgentWorker(id: id, name: name, model: model, state: state)
      }
    }

    if let data = UserDefaults.standard.data(forKey: ticketsKey),
      let tickets = try? JSONDecoder().decode([WorkloadTicket].self, from: data)
    {
      unassignedTickets = tickets
    }
  }
}

// MARK: - Balancing Strategy

public enum BalancingStrategy: String, CaseIterable {
  case leastLoaded = "Least Loaded"
  case roundRobin = "Round Robin"
  case priorityWeighted = "Priority Weighted"

  public var description: String {
    switch self {
    case .leastLoaded: return "Assign to agent with lowest current load"
    case .roundRobin: return "Distribute evenly by ticket count"
    case .priorityWeighted: return "Route critical tickets to Opus agents"
    }
  }
}
