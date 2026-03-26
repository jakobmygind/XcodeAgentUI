import AppKit
import Dependencies
import Foundation
import Observation
import UserNotifications

@Observable @MainActor
final class SessionManager {
  var activeSession: AgentSession?
  var isConnectedAsHuman: Bool = false

  var bridgeWS: BridgeWebSocket
  private let notificationManager = NotificationManager.shared

  @ObservationIgnored @Dependency(\.hapticClient) var hapticClient

  private var lastActivityDate: Date = Date()
  private var stuckCheckTask: Task<Void, Never>?
  private var stuckNotificationSent: Bool = false

  private var buildRetryCount: Int = 0
  private static let maxBuildRetries = 3

  private var tokenThresholdNotified = Set<Int>()

  private var completionNotificationSent: Bool = false

  init(bridgeWS: BridgeWebSocket) {
    self.bridgeWS = bridgeWS
    setupBridgeCallbacks()
    setupNotificationActions()
  }

  // MARK: - Session Lifecycle

  func startSession(ticketID: String, project: String, criteria: [String] = []) {
    let session = AgentSession(ticketID: ticketID, project: project)
    session.criteria = criteria.map { AcceptanceCriterion(text: $0) }
    activeSession = session

    lastActivityDate = Date()
    stuckNotificationSent = false
    buildRetryCount = 0
    tokenThresholdNotified.removeAll()
    completionNotificationSent = false

    connectAsHuman()
    startStuckDetection()

    session.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "Session started for \(ticketID)",
        from: "system"
      ))
  }

  func endSession() {
    activeSession?.isActive = false
    activeSession = nil
    stopStuckDetection()
    disconnectHuman()
  }

  // MARK: - Bridge Connection (as Human)

  func connectAsHuman() {
    bridgeWS.connect(role: .human, name: "mission-control")
    isConnectedAsHuman = true
  }

  func disconnectHuman() {
    bridgeWS.disconnect()
    isConnectedAsHuman = false
  }

  // MARK: - Send Commands

  func sendCommand(_ text: String) {
    guard let session = activeSession else { return }

    bridgeWS.send(type: "human_command", payload: text)

    session.addFeedMessage(
      FeedMessage(
        type: .humanCommand,
        content: text,
        from: "human"
      ))
  }

  func approveRequest(_ request: ApprovalRequest) {
    let payload = Self.approvalPayload(approved: true, requestID: request.messageID)
    bridgeWS.send(type: "human_approval", payload: payload)

    activeSession?.pendingApproval = nil
    activeSession?.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "Approved: \(request.description)",
        from: "human"
      ))
  }

  func denyRequest(_ request: ApprovalRequest) {
    let payload = Self.approvalPayload(approved: false, requestID: request.messageID)
    bridgeWS.send(type: "human_approval", payload: payload)

    activeSession?.pendingApproval = nil
    activeSession?.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "Denied: \(request.description)",
        from: "human"
      ))
  }

  // MARK: - Bridge Callbacks

  private func setupBridgeCallbacks() {
    bridgeWS.onConnectionChanged = { [weak self] connected in
      self?.isConnectedAsHuman = connected
    }

    bridgeWS.onMessageReceived = { [weak self] envelope in
      self?.processEnvelope(envelope)
    }
  }

  // MARK: - Notification Action Handling

  private func setupNotificationActions() {
    notificationManager.onActionReceived = { [weak self] action, context in
      Task { @MainActor [weak self] in
        self?.handleNotificationAction(action, context: context)
      }
    }
  }

  private func handleNotificationAction(_ action: NotificationAction, context: String) {
    guard let session = activeSession else { return }

    switch action {
    case .approve:
      if let request = session.pendingApproval {
        approveRequest(request)
        session.addFeedMessage(
          FeedMessage(type: .system, content: "Approved via notification", from: "human"))
      }

    case .deny:
      if let request = session.pendingApproval {
        denyRequest(request)
        session.addFeedMessage(
          FeedMessage(type: .system, content: "Denied via notification", from: "human"))
      }

    case .viewLogs:
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Viewing logs from notification", from: "system"))

    case .retryBuild:
      buildRetryCount = 0
      sendCommand("/retry-build")
      session.addFeedMessage(
        FeedMessage(
          type: .system, content: "Build retry triggered via notification", from: "human"))

    case .nudgeAgent:
      sendCommand("/status")
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Agent nudged via notification", from: "human"))
      stuckNotificationSent = false
      lastActivityDate = Date()
      notificationManager.clearStuckNotification(ticketID: session.ticketID)

    case .abortAgent:
      sendCommand("/abort")
      session.addFeedMessage(
        FeedMessage(
          type: .system, content: "Agent aborted via notification", from: "human"))

    case .viewDiff:
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Viewing diff from notification", from: "system"))

    case .pauseAgent:
      sendCommand("/pause")
      session.addFeedMessage(
        FeedMessage(
          type: .system, content: "Agent paused via notification (token threshold)",
          from: "human"))
    }
  }

  // MARK: - Stuck Detection

  private func startStuckDetection() {
    stopStuckDetection()
    stuckCheckTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        guard !Task.isCancelled else { break }
        self?.checkIfStuck()
      }
    }
  }

  private func stopStuckDetection() {
    stuckCheckTask?.cancel()
    stuckCheckTask = nil
  }

  private func checkIfStuck() {
    guard let session = activeSession, session.isActive else { return }
    guard !stuckNotificationSent else { return }

    let timeout = TimeInterval(notificationManager.stuckTimeoutMinutes * 60)
    if Date().timeIntervalSince(lastActivityDate) >= timeout {
      stuckNotificationSent = true
      notificationManager.sendAgentStuckNotification(
        ticketID: session.ticketID,
        lastActivity: lastActivityDate
      )
      session.addFeedMessage(
        FeedMessage(
          type: .system,
          content:
            "No agent activity for \(notificationManager.stuckTimeoutMinutes) minutes — notification sent",
          from: "system"
        ))
    }
  }

  private func recordActivity() {
    lastActivityDate = Date()
    if stuckNotificationSent {
      stuckNotificationSent = false
      if let session = activeSession {
        notificationManager.clearStuckNotification(ticketID: session.ticketID)
      }
    }
  }

  // MARK: - Message Processing

  private func processEnvelope(_ envelope: BridgeEnvelope) {
    guard let session = activeSession else { return }

    let payload = envelope.payload.stringValue

    if envelope.from == "agent" || envelope.from.hasPrefix("agent") {
      recordActivity()
    }

    switch envelope.type {
    case "agent_output":
      session.addFeedMessage(FeedMessage(type: .output, content: payload, from: envelope.from))

    case "agent_error":
      session.addFeedMessage(FeedMessage(type: .error, content: payload, from: envelope.from))
      checkBuildFailure(payload: payload, session: session)

    case "agent_status":
      session.addFeedMessage(FeedMessage(type: .status, content: payload, from: envelope.from))
      checkCriteriaCompletion(payload: payload, session: session)
      checkAllCriteriaMet(session: session)

    case "file_changed":
      session.addFeedMessage(
        FeedMessage(type: .fileChanged, content: payload, from: envelope.from))
      parseDiffFromPayload(payload, session: session)

    case "agent_approval_request":
      let request = ApprovalRequest(
        description: payload,
        messageID: envelope.id.uuidString
      )
      session.pendingApproval = request
      session.addFeedMessage(
        FeedMessage(type: .approval, content: payload, from: envelope.from))
      notificationManager.sendApprovalNotification(
        requestID: request.id.uuidString,
        description: payload
      )

    case "acceptance_criteria":
      parseCriteria(payload, session: session)

    case "criterion_met":
      markCriterionFromPayload(payload, session: session)
      checkAllCriteriaMet(session: session)

    case "token_usage":
      parseTokenUsage(payload, session: session)

    case "build_result":
      parseBuildResult(payload, session: session)

    default:
      break
    }
  }

  // MARK: - Build Failure Detection

  private func checkBuildFailure(payload: String, session: AgentSession) {
    let lower = payload.lowercased()
    guard lower.contains("build failed") || lower.contains("xcodebuild error")
      || lower.contains("compilation error")
    else { return }

    buildRetryCount += 1
    if buildRetryCount >= Self.maxBuildRetries {
      notificationManager.sendBuildFailedNotification(
        ticketID: session.ticketID,
        retryCount: buildRetryCount,
        error: String(payload.prefix(200))
      )
    }
  }

  private func parseBuildResult(_ payload: String, session: AgentSession) {
    let lower = payload.lowercased()
    if lower.contains("success") || lower.contains("passed") {
      buildRetryCount = 0
    } else if lower.contains("failed") || lower.contains("error") {
      buildRetryCount += 1
      if buildRetryCount >= Self.maxBuildRetries {
        notificationManager.sendBuildFailedNotification(
          ticketID: session.ticketID,
          retryCount: buildRetryCount,
          error: String(payload.prefix(200))
        )
      }
    }
  }

  // MARK: - Token Usage Tracking

  private func parseTokenUsage(_ payload: String, session: AgentSession) {
    guard let data = payload.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let used = json["tokens_used"] as? Int,
      let limit = json["token_limit"] as? Int,
      limit > 0
    else { return }

    session.tokensUsed = used
    session.tokenLimit = limit

    let percent = (used * 100) / limit
    let threshold = notificationManager.tokenUsageThresholdPercent

    if percent >= threshold && !tokenThresholdNotified.contains(threshold) {
      tokenThresholdNotified.insert(threshold)
      notificationManager.sendTokenThresholdNotification(
        ticketID: session.ticketID,
        tokensUsed: used,
        tokenLimit: limit,
        percent: percent
      )
    }

    for milestone in [90, 95, 100] where milestone > threshold {
      if percent >= milestone && !tokenThresholdNotified.contains(milestone) {
        tokenThresholdNotified.insert(milestone)
        notificationManager.sendTokenThresholdNotification(
          ticketID: session.ticketID,
          tokensUsed: used,
          tokenLimit: limit,
          percent: percent
        )
      }
    }
  }

  // MARK: - Ticket Completion Detection

  private func checkAllCriteriaMet(session: AgentSession) {
    guard !session.criteria.isEmpty else { return }
    guard session.criteria.allSatisfy({ $0.isCompleted }) else { return }
    guard session.isActive else { return }
    guard !completionNotificationSent else { return }

    completionNotificationSent = true
    notificationManager.sendTicketCompletedNotification(
      ticketID: session.ticketID,
      project: session.project,
      criteriaCount: session.criteria.count
    )

    session.addFeedMessage(
      FeedMessage(
        type: .system,
        content:
          "All \(session.criteria.count) criteria met — ticket complete notification sent",
        from: "system"
      ))

    hapticClient.perform()
  }

  // MARK: - Diff Parsing

  private func parseDiffFromPayload(_ payload: String, session: AgentSession) {
    let lines = payload.components(separatedBy: "\n")
    guard !lines.isEmpty else { return }

    var filePath = "unknown"
    var hunks: [DiffHunk] = []
    var currentLines: [DiffLine] = []
    var currentHeader = ""
    var lineNum = 0

    for line in lines {
      if line.hasPrefix("diff --git") || line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
        if line.hasPrefix("+++ b/") {
          filePath = String(line.dropFirst(6))
        }
        continue
      }

      if line.hasPrefix("@@") {
        if !currentLines.isEmpty {
          hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
          currentLines = []
        }
        currentHeader = line
        if let range = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
          lineNum = Int(line[range].dropFirst()) ?? 0
        }
        continue
      }

      if line.hasPrefix("+") {
        currentLines.append(
          DiffLine(type: .addition, content: String(line.dropFirst()), lineNumber: lineNum))
        lineNum += 1
      } else if line.hasPrefix("-") {
        currentLines.append(
          DiffLine(type: .deletion, content: String(line.dropFirst()), lineNumber: nil))
      } else {
        currentLines.append(
          DiffLine(
            type: .context, content: line.hasPrefix(" ") ? String(line.dropFirst()) : line,
            lineNumber: lineNum))
        lineNum += 1
      }
    }

    if !currentLines.isEmpty {
      hunks.append(DiffHunk(header: currentHeader, lines: currentLines))
    }

    if !hunks.isEmpty {
      session.addDiff(DiffChunk(filePath: filePath, hunks: hunks))
    }
  }

  // MARK: - Criteria

  private func parseCriteria(_ payload: String, session: AgentSession) {
    let items = payload.components(separatedBy: "\n").filter { !$0.isEmpty }
    let criteria = items.map { AcceptanceCriterion(text: $0.trimmingCharacters(in: .whitespaces)) }
    session.updateCriteria(criteria)
  }

  private func markCriterionFromPayload(_ payload: String, session: AgentSession) {
    let text = payload.trimmingCharacters(in: .whitespaces)
    if let idx = session.criteria.firstIndex(where: {
      $0.text.localizedCaseInsensitiveContains(text)
    }) {
      session.criteria[idx].isCompleted = true
      hapticClient.perform()
    }
  }

  private func checkCriteriaCompletion(payload: String, session: AgentSession) {
    for i in session.criteria.indices where !session.criteria[i].isCompleted {
      if payload.localizedCaseInsensitiveContains(session.criteria[i].text) {
        session.criteria[i].isCompleted = true
        hapticClient.perform()
      }
    }
  }

  // MARK: - JSON Helpers

  private static func approvalPayload(approved: Bool, requestID: String) -> String {
    let dict: [String: Any] = ["approved": approved, "request_id": requestID]
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
      let json = String(data: data, encoding: .utf8)
    else { return "{}" }
    return json
  }
}
