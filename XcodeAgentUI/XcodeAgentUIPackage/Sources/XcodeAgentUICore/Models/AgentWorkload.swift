import Foundation
import Observation

// MARK: - Agent Worker

@Observable
public final class AgentWorker: Identifiable, Hashable {
  public let id: UUID
  public var name: String
  public var model: AgentModel
  public var state: AgentWorkerState
  public var assignedTickets: [WorkloadTicket]
  public var schedule: AgentSchedule?
  public var cpuLoad: Double  // 0.0 - 1.0 synthetic load metric

  public var ticketCount: Int { assignedTickets.count }
  public var isAvailable: Bool { state == .idle || state == .working }
  public var isScheduled: Bool { schedule != nil }

  public init(
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

  public func recalculateLoad() {
    let base = Double(assignedTickets.count) * 0.25
    let priorityBoost = assignedTickets.reduce(0.0) { acc, t in
      acc + (t.priority == .critical ? 0.15 : t.priority == .high ? 0.1 : 0.0)
    }
    cpuLoad = min(1.0, base + priorityBoost)
  }

  public static func == (lhs: AgentWorker, rhs: AgentWorker) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public enum AgentWorkerState: String, CaseIterable, Sendable {
  case idle
  case working
  case paused
  case offline
  case scheduled

  public var label: String {
    switch self {
    case .idle: return "Idle"
    case .working: return "Working"
    case .paused: return "Paused"
    case .offline: return "Offline"
    case .scheduled: return "Scheduled"
    }
  }

  public var color: String {
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

public struct WorkloadTicket: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public var ticketID: String
  public var title: String
  public var project: String
  public var provider: String
  public var priority: TicketPriority
  public var assignedAgentID: UUID?
  public var createdAt: Date
  public var estimatedMinutes: Int?

  public init(
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

public enum TicketPriority: String, CaseIterable, Codable, Sendable {
  case critical
  case high
  case medium
  case low

  public var label: String { rawValue.capitalized }

  public var sortOrder: Int {
    switch self {
    case .critical: return 0
    case .high: return 1
    case .medium: return 2
    case .low: return 3
    }
  }
}

// MARK: - Agent Schedule

public struct AgentSchedule: Identifiable, Codable, Hashable, Sendable {
  public let id: UUID
  public var startTime: Date
  public var endTime: Date
  public var recurrence: ScheduleRecurrence
  public var label: String

  public init(
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

  public var isActive: Bool {
    let now = Date()
    return now >= startTime && now <= endTime
  }

  public var durationFormatted: String {
    let interval = endTime.timeIntervalSince(startTime)
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
  }
}

public enum ScheduleRecurrence: String, CaseIterable, Codable, Sendable {
  case once = "Once"
  case daily = "Daily"
  case weekdays = "Weekdays"
  case weekly = "Weekly"
}
