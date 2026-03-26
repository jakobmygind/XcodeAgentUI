import Foundation

/// Parses agent runner logs and bridge messages into TicketRun records
final class LogParser {

  /// Parse a completed session from bridge messages into a TicketRun
  static func parseSession(
    ticketID: String,
    project: String,
    agentModel: String,
    startedAt: Date,
    finishedAt: Date,
    messages: [String]
  ) -> TicketRun {
    var buildSucceeded = false
    var testsSucceeded = false
    var retryCount = 0
    var outcome: RunOutcome = .failure
    var inputTokens = 0
    var outputTokens = 0

    for msg in messages {
      let lower = msg.lowercased()

      // Detect build results
      if lower.contains("build succeeded") || lower.contains("build passed") {
        buildSucceeded = true
      }

      // Detect test results
      if lower.contains("tests passed") || lower.contains("test suite passed")
        || lower.contains("all tests passed")
      {
        testsSucceeded = true
      }

      // Detect retries / self-healing
      if lower.contains("retrying") || lower.contains("self-heal")
        || lower.contains("retry attempt") || lower.contains("fix attempt")
      {
        retryCount += 1
      }

      // Detect completion
      if lower.contains("ticket completed") || lower.contains("task completed")
        || lower.contains("pr created") || lower.contains("pull request opened")
      {
        outcome = .success
      }
      if lower.contains("aborted") || lower.contains("cancelled") {
        outcome = .aborted
      }
      if lower.contains("timed out") || lower.contains("timeout") {
        outcome = .timeout
      }

      // Parse token usage from agent output
      // Expected format: "tokens: input=12345 output=6789" or "usage: 12345 in / 6789 out"
      if lower.contains("token") {
        if let inMatch = extractNumber(from: msg, after: "input=") {
          inputTokens += inMatch
        }
        if let outMatch = extractNumber(from: msg, after: "output=") {
          outputTokens += outMatch
        }
        // Alt format: "12345 in / 6789 out"
        if let inMatch = extractNumber(from: msg, after: "usage:") {
          inputTokens += inMatch
        }
      }
    }

    // Estimate tokens if none parsed
    if inputTokens == 0 {
      let durationMin = finishedAt.timeIntervalSince(startedAt) / 60
      inputTokens = agentModel == "opus"
        ? Int(durationMin * 3000)
        : Int(durationMin * 2000)
      outputTokens = inputTokens / 3
    }

    return TicketRun(
      id: UUID().uuidString,
      ticketID: ticketID,
      project: project,
      agentModel: agentModel,
      startedAt: startedAt,
      finishedAt: finishedAt,
      outcome: outcome,
      buildSucceeded: buildSucceeded,
      testsSucceeded: testsSucceeded,
      retryCount: retryCount,
      inputTokens: inputTokens,
      outputTokens: outputTokens
    )
  }

  /// Scan a log directory for completed run files and parse them
  static func scanLogDirectory(at path: String) -> [TicketRun] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: path) else { return [] }

    var runs: [TicketRun] = []

    for file in files where file.hasSuffix(".log") || file.hasSuffix(".json") {
      let fullPath = (path as NSString).appendingPathComponent(file)

      if file.hasSuffix(".json") {
        // Try parsing structured JSON log
        if let run = parseJSONLog(at: fullPath) {
          runs.append(run)
        }
      } else {
        // Parse plain text log
        if let run = parseTextLog(at: fullPath) {
          runs.append(run)
        }
      }
    }

    return runs
  }

  // MARK: - JSON Log Parsing

  private static func parseJSONLog(at path: String) -> TicketRun? {
    guard let data = FileManager.default.contents(atPath: path),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    guard
      let ticketID = json["ticketID"] as? String ?? json["ticket_id"] as? String,
      let project = json["project"] as? String,
      let model = json["model"] as? String ?? json["agent_model"] as? String,
      let startTS = json["started_at"] as? TimeInterval ?? json["startedAt"] as? TimeInterval,
      let endTS = json["finished_at"] as? TimeInterval ?? json["finishedAt"] as? TimeInterval
    else { return nil }

    let outcomeStr = json["outcome"] as? String ?? json["status"] as? String ?? "failure"

    return TicketRun(
      id: json["id"] as? String ?? UUID().uuidString,
      ticketID: ticketID,
      project: project,
      agentModel: model.lowercased(),
      startedAt: Date(timeIntervalSince1970: startTS),
      finishedAt: Date(timeIntervalSince1970: endTS),
      outcome: RunOutcome(rawValue: outcomeStr) ?? .failure,
      buildSucceeded: json["build_succeeded"] as? Bool ?? false,
      testsSucceeded: json["tests_succeeded"] as? Bool ?? false,
      retryCount: json["retry_count"] as? Int ?? 0,
      inputTokens: json["input_tokens"] as? Int ?? 0,
      outputTokens: json["output_tokens"] as? Int ?? 0
    )
  }

  // MARK: - Text Log Parsing

  private static func parseTextLog(at path: String) -> TicketRun? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let lines = content.components(separatedBy: .newlines)
    guard lines.count > 5 else { return nil }

    // Try to extract metadata from first few lines
    var ticketID = ""
    var project = ""
    var model = "sonnet"

    for line in lines.prefix(10) {
      if line.contains("ticket:") || line.contains("Ticket:") {
        ticketID = extractValue(from: line) ?? ""
      }
      if line.contains("project:") || line.contains("Project:") {
        project = extractValue(from: line) ?? ""
      }
      if line.lowercased().contains("opus") {
        model = "opus"
      }
    }

    guard !ticketID.isEmpty else { return nil }

    // Use file dates as fallback
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let created = attrs?[.creationDate] as? Date ?? Date()
    let modified = attrs?[.modificationDate] as? Date ?? Date()

    return parseSession(
      ticketID: ticketID,
      project: project,
      agentModel: model,
      startedAt: created,
      finishedAt: modified,
      messages: lines
    )
  }

  // MARK: - Helpers

  private static func extractNumber(from string: String, after prefix: String) -> Int? {
    guard let range = string.range(of: prefix, options: .caseInsensitive) else { return nil }
    let after = string[range.upperBound...]
    let digits = after.prefix(while: { $0.isNumber })
    return Int(digits)
  }

  private static func extractValue(from line: String) -> String? {
    let parts = line.components(separatedBy: ":")
    guard parts.count >= 2 else { return nil }
    return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
  }
}
