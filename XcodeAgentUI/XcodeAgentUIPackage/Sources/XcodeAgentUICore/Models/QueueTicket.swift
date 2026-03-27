import Foundation

/// A ticket waiting in the queue or actively being worked on
public struct QueueTicket: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var ticketID: String
  public var project: String
  public var providerType: String
  public var model: String  // "Sonnet" or "Opus"
  public var priority: Priority
  public var status: Status
  public var assignedAgent: String?
  public var addedAt: Date
  public var startedAt: Date?
  public var tags: [String]

  public init(
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

  public static func == (lhs: QueueTicket, rhs: QueueTicket) -> Bool {
    lhs.id == rhs.id
  }

  public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3

    public var label: String {
      switch self {
      case .low: return "Low"
      case .medium: return "Medium"
      case .high: return "High"
      case .critical: return "Critical"
      }
    }

    public var icon: String {
      switch self {
      case .low: return "arrow.down"
      case .medium: return "minus"
      case .high: return "arrow.up"
      case .critical: return "exclamationmark.2"
      }
    }

    public var color: String {
      switch self {
      case .low: return "gray"
      case .medium: return "blue"
      case .high: return "orange"
      case .critical: return "red"
      }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  public enum Status: String, Codable, Sendable {
    case pending
    case running
    case paused
    case completed
    case failed

    public var label: String {
      switch self {
      case .pending: return "Pending"
      case .running: return "Running"
      case .paused: return "Paused"
      case .completed: return "Completed"
      case .failed: return "Failed"
      }
    }

    public var icon: String {
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
public struct ConcurrencyLimits: Codable, Equatable, Sendable {
  public var maxSonnet: Int
  public var maxOpus: Int

  public static let `default` = ConcurrencyLimits(maxSonnet: 2, maxOpus: 1)

  public init(maxSonnet: Int, maxOpus: Int) {
    self.maxSonnet = maxSonnet
    self.maxOpus = maxOpus
  }
}

/// Rules for auto-assigning agents based on ticket tags/patterns
public struct AutoAssignRule: Identifiable, Codable, Sendable {
  public let id: UUID
  public var pattern: String  // tag or keyword to match
  public var assignModel: String  // "Sonnet" or "Opus"

  public init(pattern: String, assignModel: String) {
    self.id = UUID()
    self.pattern = pattern
    self.assignModel = assignModel
  }
}
