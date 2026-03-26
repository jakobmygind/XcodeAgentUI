import Foundation
import Observation

// MARK: - Agent Worker

@Observable
final class AgentWorker: Identifiable, Hashable {
  let id: UUID
  var name: String
  var model: AgentModel
  var state: AgentWorkerState
  var assignedTickets: [WorkloadTicket]
  var schedule: AgentSchedule?
  var cpuLoad: Double  // 0.0 - 1.0 synthetic load metric

  var ticketCount: Int { assignedTickets.count }
  var isAvailable: Bool { state == .idle || state == .working }
  var isScheduled: Bool { schedule != nil }

  init(
    id: UUID = UUID(),
    name: String,
    model: AgentModel = .sonnet,
    state: AgentWorkerState = .idle,
    assignedTickets: [WorkloadTicket] = [],
    schedule: AgentSchedule? = nil
  ) {
    self.id = id
    self.name = name
    self.model = model
    self.state = state
    self.assignedTickets = assignedTickets
    self.schedule = schedule
    self.cpuLoad = 0.0
    recalculateLoad()
  }

  func recalculateLoad() {
    let base = Double(assignedTickets.count) * 0.25
    let priorityBoost = assignedTickets.reduce(0.0) { acc, t in
      acc + (t.priority == .critical ? 0.15 : t.priority == .high ? 0.1 : 0.0)
    }
    cpuLoad = min(1.0, base + priorityBoost)
  }

  static func == (lhs: AgentWorker, rhs: AgentWorker) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

enum AgentWorkerState: String, CaseIterable {
  case idle
  case working
  case paused
  case offline
  case scheduled

  var label: String {
    switch self {
    case .idle: return "Idle"
    case .working: return "Working"
    case .paused: return "Paused"
    case .offline: return "Offline"
    case .scheduled: return "Scheduled"
    }
  }

  var color: String {
    switch self {
    case .idle: return "green"
    case .working: return "blue"
    case .paused: return "yellow"
    case .offline: return "gray"
    case .scheduled: return "purple"
    }
  }
}

// MARK: - Workload Ticket

struct WorkloadTicket: Identifiable, Hashable, Codable {
  let id: UUID
  var ticketID: String
  var title: String
  var project: String
  var provider: String
  var priority: TicketPriority
  var assignedAgentID: UUID?
  var createdAt: Date
  var estimatedMinutes: Int?

  init(
    id: UUID = UUID(),
    ticketID: String,
    title: String,
    project: String,
    provider: String = "github",
    priority: TicketPriority = .medium,
    assignedAgentID: UUID? = nil,
    createdAt: Date = Date(),
    estimatedMinutes: Int? = nil
  ) {
    self.id = id
    self.ticketID = ticketID
    self.title = title
    self.project = project
    self.provider = provider
    self.priority = priority
    self.assignedAgentID = assignedAgentID
    self.createdAt = createdAt
    self.estimatedMinutes = estimatedMinutes
  }
}

enum TicketPriority: String, CaseIterable, Codable {
  case critical
  case high
  case medium
  case low

  var label: String { rawValue.capitalized }

  var sortOrder: Int {
    switch self {
    case .critical: return 0
    case .high: return 1
    case .medium: return 2
    case .low: return 3
    }
  }
}

// MARK: - Agent Schedule

struct AgentSchedule: Identifiable, Codable, Hashable {
  let id: UUID
  var startTime: Date
  var endTime: Date
  var recurrence: ScheduleRecurrence
  var label: String

  init(
    id: UUID = UUID(),
    startTime: Date,
    endTime: Date,
    recurrence: ScheduleRecurrence = .once,
    label: String = ""
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.recurrence = recurrence
    self.label = label
  }

  var isActive: Bool {
    let now = Date()
    return now >= startTime && now <= endTime
  }

  var durationFormatted: String {
    let interval = endTime.timeIntervalSince(startTime)
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
  }
}

enum ScheduleRecurrence: String, CaseIterable, Codable {
  case once = "Once"
  case daily = "Daily"
  case weekdays = "Weekdays"
  case weekly = "Weekly"
}
