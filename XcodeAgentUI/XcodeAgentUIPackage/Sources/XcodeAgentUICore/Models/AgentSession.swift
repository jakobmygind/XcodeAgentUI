import Foundation
import Observation

/// Represents an active agent session tied to a specific ticket
@Observable
public final class AgentSession: Identifiable {
  public let id: UUID
  public let ticketID: String
  public let project: String
  public let startedAt: Date

  public var isActive: Bool = true
  public var diffChunks: [DiffChunk] = []
  public var criteria: [AcceptanceCriterion] = []
  public var feedMessages: [FeedMessage] = []
  public var pendingApproval: ApprovalRequest?
  public var tokensUsed: Int = 0
  public var tokenLimit: Int = 0

  public var tokenUsagePercent: Int {
    guard tokenLimit > 0 else { return 0 }
    return (tokensUsed * 100) / tokenLimit
  }

  public init(ticketID: String, project: String) {
    self.id = UUID()
    self.ticketID = ticketID
    self.project = project
    self.startedAt = Date()
  }

  public func addDiff(_ chunk: DiffChunk) {
    diffChunks.append(chunk)
  }

  public func addFeedMessage(_ message: FeedMessage) {
    if feedMessages.count > 500 {
      feedMessages.removeFirst(50)
    }
    feedMessages.append(message)
  }

  public func updateCriteria(_ criteria: [AcceptanceCriterion]) {
    self.criteria = criteria
  }

  public func markCriterion(id: UUID, completed: Bool) {
    if let idx = criteria.firstIndex(where: { $0.id == id }) {
      criteria[idx].isCompleted = completed
    }
  }
}

// MARK: - Supporting Types

public struct DiffChunk: Identifiable, Sendable {
  public let id = UUID()
  public let filePath: String
  public let hunks: [DiffHunk]
  public let timestamp: Date

  public init(filePath: String, hunks: [DiffHunk], timestamp: Date = Date()) {
    self.filePath = filePath
    self.hunks = hunks
    self.timestamp = timestamp
  }
}

public struct DiffHunk: Identifiable, Sendable {
  public let id = UUID()
  public let header: String  // e.g. @@ -10,5 +10,8 @@
  public let lines: [DiffLine]
}

public struct DiffLine: Identifiable, Sendable {
  public let id = UUID()
  public let type: LineType
  public let content: String
  public let lineNumber: Int?

  public enum LineType: Sendable {
    case addition
    case deletion
    case context
  }
}

public struct AcceptanceCriterion: Identifiable, Sendable {
  public let id: UUID
  public var text: String
  public var isCompleted: Bool

  public init(text: String, isCompleted: Bool = false) {
    self.id = UUID()
    self.text = text
    self.isCompleted = isCompleted
  }
}

public struct FeedMessage: Identifiable, Sendable {
  public let id = UUID()
  public let type: FeedMessageType
  public let content: String
  public let timestamp: Date
  public let from: String

  public init(type: FeedMessageType, content: String, from: String = "agent", timestamp: Date = Date()) {
    self.type = type
    self.content = content
    self.from = from
    self.timestamp = timestamp
  }

  public enum FeedMessageType: String, Sendable {
    case output
    case error
    case status
    case fileChanged
    case approval
    case humanCommand
    case system
  }
}

public struct ApprovalRequest: Identifiable, Sendable {
  public let id = UUID()
  public let description: String
  public let detail: String
  public let timestamp: Date
  public let messageID: String

  public init(description: String, detail: String = "", messageID: String = "", timestamp: Date = Date()) {
    self.description = description
    self.detail = detail
    self.messageID = messageID
    self.timestamp = timestamp
  }
}
