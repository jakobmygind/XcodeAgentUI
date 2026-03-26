import Foundation

/// A ticket waiting in the queue or actively being worked on
struct QueueTicket: Identifiable, Codable, Equatable {
  let id: UUID
  var ticketID: String
  var project: String
  var providerType: String
  var model: String  // "Sonnet" or "Opus"
  var priority: Priority
  var status: Status
  var assignedAgent: String?
  var addedAt: Date
  var startedAt: Date?
  var tags: [String]

  init(
    ticketID: String,
    project: String,
    providerType: String,
    model: String = "Sonnet",
    priority: Priority = .medium,
    tags: [String] = []
  ) {
    self.id = UUID()
    self.ticketID = ticketID
    self.project = project
    self.providerType = providerType
    self.model = model
    self.priority = priority
    self.status = .pending
    self.assignedAgent = nil
    self.addedAt = Date()
    self.startedAt = nil
    self.tags = tags
  }

  static func == (lhs: QueueTicket, rhs: QueueTicket) -> Bool {
    lhs.id == rhs.id
  }

  enum Priority: Int, Codable, CaseIterable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    var label: String {
      switch self {
      case .low: return "Low"
      case .medium: return "Medium"
      case .high: return "High"
      case .critical: return "Critical"
      }
    }

    var icon: String {
      switch self {
      case .low: return "arrow.down"
      case .medium: return "minus"
      case .high: return "arrow.up"
      case .critical: return "exclamationmark.2"
      }
    }

    var color: String {
      switch self {
      case .low: return "gray"
      case .medium: return "blue"
      case .high: return "orange"
      case .critical: return "red"
      }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  enum Status: String, Codable {
    case pending
    case running
    case paused
    case completed
    case failed

    var label: String {
      switch self {
      case .pending: return "Pending"
      case .running: return "Running"
      case .paused: return "Paused"
      case .completed: return "Completed"
      case .failed: return "Failed"
      }
    }

    var icon: String {
      switch self {
      case .pending: return "clock"
      case .running: return "play.fill"
      case .paused: return "pause.fill"
      case .completed: return "checkmark.circle.fill"
      case .failed: return "xmark.circle.fill"
      }
    }
  }
}

/// Concurrency limits per model type
struct ConcurrencyLimits: Codable, Equatable {
  var maxSonnet: Int
  var maxOpus: Int

  static let `default` = ConcurrencyLimits(maxSonnet: 2, maxOpus: 1)
}

/// Rules for auto-assigning agents based on ticket tags/patterns
struct AutoAssignRule: Identifiable, Codable {
  let id: UUID
  var pattern: String  // tag or keyword to match
  var assignModel: String  // "Sonnet" or "Opus"

  init(pattern: String, assignModel: String) {
    self.id = UUID()
    self.pattern = pattern
    self.assignModel = assignModel
  }
}
