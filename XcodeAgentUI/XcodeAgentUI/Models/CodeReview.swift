import Foundation
import Observation

/// Manages the full code review state for agent-produced diffs
@Observable
final class CodeReview: Identifiable {
  let id: UUID
  let sessionID: UUID
  let ticketID: String
  let createdAt: Date

  var files: [ReviewFile] = []
  var verdict: ReviewVerdict = .pending
  var summaryComment: String = ""

  var approvedCount: Int { files.filter { $0.status == .approved }.count }
  var changesRequestedCount: Int { files.filter { $0.status == .changesRequested }.count }
  var pendingCount: Int { files.filter { $0.status == .pending }.count }
  var totalComments: Int { files.reduce(0) { $0 + $1.comments.count } }

  init(sessionID: UUID, ticketID: String) {
    self.id = UUID()
    self.sessionID = sessionID
    self.ticketID = ticketID
    self.createdAt = Date()
  }

  func ingestDiffs(_ chunks: [DiffChunk]) {
    for chunk in chunks {
      if let idx = files.firstIndex(where: { $0.filePath == chunk.filePath }) {
        files[idx].hunks = chunk.hunks
        files[idx].lastUpdated = chunk.timestamp
      } else {
        files.append(
          ReviewFile(filePath: chunk.filePath, hunks: chunk.hunks, timestamp: chunk.timestamp))
      }
    }
  }

  func approveAll() {
    for i in files.indices {
      files[i].status = .approved
    }
    verdict = .approved
  }

  func approveFile(id: UUID) {
    if let idx = files.firstIndex(where: { $0.id == id }) {
      files[idx].status = .approved
    }
  }

  func requestChangesFile(id: UUID) {
    if let idx = files.firstIndex(where: { $0.id == id }) {
      files[idx].status = .changesRequested
    }
  }

  func resetFile(id: UUID) {
    if let idx = files.firstIndex(where: { $0.id == id }) {
      files[idx].status = .pending
    }
  }

  func addComment(fileID: UUID, line: Int, content: String) {
    guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    if let idx = files.firstIndex(where: { $0.id == fileID }) {
      let comment = ReviewComment(
        line: line,
        content: content,
        author: "reviewer"
      )
      files[idx].comments.append(comment)
    }
  }

  func removeComment(fileID: UUID, commentID: UUID) {
    if let idx = files.firstIndex(where: { $0.id == fileID }) {
      files[idx].comments.removeAll { $0.id == commentID }
    }
  }

  func exportAsMarkdown() -> String {
    var md = "# Code Review: \(ticketID)\n"
    md += "**Date:** \(formatted(createdAt))\n"
    md += "**Verdict:** \(verdict.label)\n"
    md += "**Files:** \(files.count) | **Comments:** \(totalComments)\n\n"

    if !summaryComment.isEmpty {
      md += "## Summary\n\(summaryComment)\n\n"
    }

    for file in files {
      md += "---\n"
      md += "### \(file.filePath) — \(file.status.label)\n\n"

      if !file.comments.isEmpty {
        md += "#### Comments\n"
        for comment in file.comments {
          md +=
            "- **Line \(comment.line)** (\(comment.author), \(formatted(comment.timestamp))): \(comment.content)\n"
        }
        md += "\n"
      }

      md += "```diff\n"
      for hunk in file.hunks {
        md += "\(hunk.header)\n"
        for line in hunk.lines {
          switch line.type {
          case .addition: md += "+\(line.content)\n"
          case .deletion: md += "-\(line.content)\n"
          case .context: md += " \(line.content)\n"
          }
        }
      }
      md += "```\n\n"
    }

    return md
  }

  private func formatted(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
  }
}

// MARK: - Supporting Types

struct ReviewFile: Identifiable {
  let id = UUID()
  var filePath: String
  var hunks: [DiffHunk]
  var status: FileReviewStatus = .pending
  var comments: [ReviewComment] = []
  var lastUpdated: Date

  init(filePath: String, hunks: [DiffHunk], timestamp: Date = Date()) {
    self.filePath = filePath
    self.hunks = hunks
    self.lastUpdated = timestamp
  }

  var fileExtension: String {
    (filePath as NSString).pathExtension
  }

  var fileName: String {
    (filePath as NSString).lastPathComponent
  }

  var additions: Int { hunks.flatMap(\.lines).filter { $0.type == .addition }.count }
  var deletions: Int { hunks.flatMap(\.lines).filter { $0.type == .deletion }.count }
}

struct ReviewComment: Identifiable {
  let id = UUID()
  let line: Int
  let content: String
  let author: String
  let timestamp: Date

  init(line: Int, content: String, author: String = "reviewer", timestamp: Date = Date()) {
    self.line = line
    self.content = content
    self.author = author
    self.timestamp = timestamp
  }
}

enum FileReviewStatus: String {
  case pending
  case approved
  case changesRequested

  var label: String {
    switch self {
    case .pending: return "Pending"
    case .approved: return "Approved"
    case .changesRequested: return "Changes Requested"
    }
  }

  var icon: String {
    switch self {
    case .pending: return "circle"
    case .approved: return "checkmark.circle.fill"
    case .changesRequested: return "xmark.circle.fill"
    }
  }

  var color: String {
    switch self {
    case .pending: return "secondary"
    case .approved: return "green"
    case .changesRequested: return "orange"
    }
  }
}

enum ReviewVerdict: String {
  case pending
  case approved
  case changesRequested

  var label: String {
    switch self {
    case .pending: return "Pending Review"
    case .approved: return "Approved"
    case .changesRequested: return "Changes Requested"
    }
  }
}
