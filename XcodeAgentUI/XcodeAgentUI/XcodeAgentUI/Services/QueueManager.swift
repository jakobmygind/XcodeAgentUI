import Combine
import Foundation

/// Manages the ticket queue with persistence, concurrency limits, and auto-assignment
class QueueManager: ObservableObject {
  @Published var tickets: [QueueTicket] = []
  @Published var concurrencyLimits: ConcurrencyLimits = .default {
    didSet { saveLimits(); processQueue() }
  }
  @Published var autoAssignRules: [AutoAssignRule] = [] {
    didSet { saveRules() }
  }
  @Published var isAutoAssignEnabled: Bool = true {
    didSet { UserDefaults.standard.set(isAutoAssignEnabled, forKey: "queueAutoAssign") }
  }

  private let ticketsKey = "queueTickets"
  private let limitsKey = "queueConcurrencyLimits"
  private let rulesKey = "queueAutoAssignRules"

  /// Callback fired when a ticket should be dispatched to an agent
  var onDispatch: ((QueueTicket) -> Void)?

  init() {
    loadTickets()
    loadLimits()
    loadRules()
    isAutoAssignEnabled = UserDefaults.standard.object(forKey: "queueAutoAssign") as? Bool ?? true
  }

  // MARK: - Queue Operations

  func addTicket(_ ticket: QueueTicket) {
    var t = ticket
    if isAutoAssignEnabled {
      t.model = autoAssignModel(for: t)
    }
    // Insert by priority: find first ticket with lower priority
    if let idx = tickets.firstIndex(where: {
      $0.status == .pending && $0.priority < t.priority
    }) {
      tickets.insert(t, at: idx)
    } else {
      tickets.append(t)
    }
    saveTickets()
    processQueue()
  }

  func removeTicket(id: UUID) {
    tickets.removeAll { $0.id == id }
    saveTickets()
  }

  func moveTicket(from source: IndexSet, to destination: Int) {
    tickets.move(fromOffsets: source, toOffset: destination)
    saveTickets()
  }

  func reorderTicket(id: UUID, to newIndex: Int) {
    guard let currentIndex = tickets.firstIndex(where: { $0.id == id }) else { return }
    let ticket = tickets.remove(at: currentIndex)
    let clampedIndex = min(max(0, newIndex), tickets.count)
    tickets.insert(ticket, at: clampedIndex)
    saveTickets()
  }

  func updatePriority(id: UUID, priority: QueueTicket.Priority) {
    guard let idx = tickets.firstIndex(where: { $0.id == id }) else { return }
    tickets[idx].priority = priority
    saveTickets()
  }

  // MARK: - Agent Control

  func pauseTicket(id: UUID) {
    guard let idx = tickets.firstIndex(where: { $0.id == id }),
      tickets[idx].status == .running
    else { return }
    tickets[idx].status = .paused
    saveTickets()
  }

  func resumeTicket(id: UUID) {
    guard let idx = tickets.firstIndex(where: { $0.id == id }),
      tickets[idx].status == .paused
    else { return }
    tickets[idx].status = .pending
    tickets[idx].assignedAgent = nil
    tickets[idx].startedAt = nil
    saveTickets()
    processQueue()
  }

  func markCompleted(id: UUID) {
    guard let idx = tickets.firstIndex(where: { $0.id == id }) else { return }
    tickets[idx].status = .completed
    saveTickets()
    processQueue()
  }

  func markFailed(id: UUID) {
    guard let idx = tickets.firstIndex(where: { $0.id == id }) else { return }
    tickets[idx].status = .failed
    saveTickets()
    processQueue()
  }

  // MARK: - Queue Processing

  /// Attempts to dispatch pending tickets within concurrency limits
  func processQueue() {
    let runningSonnet = tickets.filter { $0.status == .running && $0.model == "Sonnet" }.count
    let runningOpus = tickets.filter { $0.status == .running && $0.model == "Opus" }.count

    var availSonnet = concurrencyLimits.maxSonnet - runningSonnet
    var availOpus = concurrencyLimits.maxOpus - runningOpus

    for i in tickets.indices {
      guard tickets[i].status == .pending else { continue }
      guard availSonnet > 0 || availOpus > 0 else { break }

      if tickets[i].model == "Sonnet" && availSonnet > 0 {
        tickets[i].status = .running
        tickets[i].startedAt = Date()
        tickets[i].assignedAgent = "agent:sonnet-\(runningSonnet + (concurrencyLimits.maxSonnet - availSonnet) + 1)"
        availSonnet -= 1
        onDispatch?(tickets[i])
      } else if tickets[i].model == "Opus" && availOpus > 0 {
        tickets[i].status = .running
        tickets[i].startedAt = Date()
        tickets[i].assignedAgent = "agent:opus-\(runningOpus + (concurrencyLimits.maxOpus - availOpus) + 1)"
        availOpus -= 1
        onDispatch?(tickets[i])
      }
    }
    saveTickets()
  }

  // MARK: - Auto-Assignment

  func addRule(_ rule: AutoAssignRule) {
    autoAssignRules.append(rule)
  }

  func removeRule(id: UUID) {
    autoAssignRules.removeAll { $0.id == id }
  }

  private func autoAssignModel(for ticket: QueueTicket) -> String {
    for rule in autoAssignRules {
      let pattern = rule.pattern.lowercased()
      if ticket.tags.contains(where: { $0.lowercased().contains(pattern) })
        || ticket.ticketID.lowercased().contains(pattern)
        || ticket.project.lowercased().contains(pattern)
      {
        return rule.assignModel
      }
    }
    return ticket.model
  }

  // MARK: - Computed

  var pendingCount: Int { tickets.filter { $0.status == .pending }.count }
  var runningCount: Int { tickets.filter { $0.status == .running }.count }
  var pausedCount: Int { tickets.filter { $0.status == .paused }.count }
  var completedCount: Int { tickets.filter { $0.status == .completed || $0.status == .failed }.count }

  var runningSonnetCount: Int { tickets.filter { $0.status == .running && $0.model == "Sonnet" }.count }
  var runningOpusCount: Int { tickets.filter { $0.status == .running && $0.model == "Opus" }.count }

  // MARK: - Persistence

  private func saveTickets() {
    if let data = try? JSONEncoder().encode(tickets) {
      UserDefaults.standard.set(data, forKey: ticketsKey)
    }
  }

  private func loadTickets() {
    guard let data = UserDefaults.standard.data(forKey: ticketsKey),
      let saved = try? JSONDecoder().decode([QueueTicket].self, from: data)
    else { return }
    tickets = saved
  }

  private func saveLimits() {
    if let data = try? JSONEncoder().encode(concurrencyLimits) {
      UserDefaults.standard.set(data, forKey: limitsKey)
    }
  }

  private func loadLimits() {
    guard let data = UserDefaults.standard.data(forKey: limitsKey),
      let saved = try? JSONDecoder().decode(ConcurrencyLimits.self, from: data)
    else { return }
    concurrencyLimits = saved
  }

  private func saveRules() {
    if let data = try? JSONEncoder().encode(autoAssignRules) {
      UserDefaults.standard.set(data, forKey: rulesKey)
    }
  }

  private func loadRules() {
    guard let data = UserDefaults.standard.data(forKey: rulesKey),
      let saved = try? JSONDecoder().decode([AutoAssignRule].self, from: data)
    else { return }
    autoAssignRules = saved
  }

  /// Remove all completed/failed tickets
  func clearCompleted() {
    tickets.removeAll { $0.status == .completed || $0.status == .failed }
    saveTickets()
  }
}
