import Foundation
import Observation

/// Represents an active agent session tied to a specific ticket
@Observable
final class AgentSession: Identifiable {
  let id: UUID
  let ticketID: String
  let project: String
  let startedAt: Date

  var isActive: Bool = true
  var diffChunks: [DiffChunk] = []
  var criteria: [AcceptanceCriterion] = []
  var feedMessages: [FeedMessage] = []
  var pendingApproval: ApprovalRequest?
  var tokensUsed: Int = 0
  var tokenLimit: Int = 0

  var tokenUsagePercent: Int {
    guard tokenLimit > 0 else { return 0 }
    return (tokensUsed * 100) / tokenLimit
  }

  init(ticketID: String, project: String) {
    self.id = UUID()
    self.ticketID = ticketID
    self.project = project
    self.startedAt = Date()
  }

  func addDiff(_ chunk: DiffChunk) {
    diffChunks.append(chunk)
  }

  func addFeedMessage(_ message: FeedMessage) {
    if feedMessages.count > 500 {
      feedMessages.removeFirst(50)
    }
    feedMessages.append(message)
  }

  func updateCriteria(_ criteria: [AcceptanceCriterion]) {
    self.criteria = criteria
  }

  func markCriterion(id: UUID, completed: Bool) {
    if let idx = criteria.firstIndex(where: { $0.id == id }) {
      criteria[idx].isCompleted = completed
    }
  }
}

// MARK: - Supporting Types

struct DiffChunk: Identifiable {
  let id = UUID()
  let filePath: String
  let hunks: [DiffHunk]
  let timestamp: Date

  init(filePath: String, hunks: [DiffHunk], timestamp: Date = Date()) {
    self.filePath = filePath
    self.hunks = hunks
    self.timestamp = timestamp
  }
}

struct DiffHunk: Identifiable {
  let id = UUID()
  let header: String  // e.g. @@ -10,5 +10,8 @@
  let lines: [DiffLine]
}

struct DiffLine: Identifiable {
  let id = UUID()
  let type: LineType
  let content: String
  let lineNumber: Int?

  enum LineType {
    case addition
    case deletion
    case context
  }
}

struct AcceptanceCriterion: Identifiable {
  let id: UUID
  var text: String
  var isCompleted: Bool

  init(text: String, isCompleted: Bool = false) {
    self.id = UUID()
    self.text = text
    self.isCompleted = isCompleted
  }
}

struct FeedMessage: Identifiable {
  let id = UUID()
  let type: FeedMessageType
  let content: String
  let timestamp: Date
  let from: String

  init(type: FeedMessageType, content: String, from: String = "agent", timestamp: Date = Date()) {
    self.type = type
    self.content = content
    self.from = from
    self.timestamp = timestamp
  }

  enum FeedMessageType: String {
    case output
    case error
    case status
    case fileChanged
    case approval
    case humanCommand
    case system
  }
}

struct ApprovalRequest: Identifiable {
  let id = UUID()
  let description: String
  let detail: String
  let timestamp: Date
  let messageID: String

  init(description: String, detail: String = "", messageID: String = "", timestamp: Date = Date()) {
    self.description = description
    self.detail = detail
    self.messageID = messageID
    self.timestamp = timestamp
  }
}
