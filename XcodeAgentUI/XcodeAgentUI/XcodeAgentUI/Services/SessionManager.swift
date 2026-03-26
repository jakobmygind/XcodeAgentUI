import AppKit
import Combine
import Foundation
import UserNotifications

/// Manages the active agent session, bridging WebSocket messages to session state
class SessionManager: ObservableObject {
  @Published var activeSession: AgentSession?
  @Published var isConnectedAsHuman: Bool = false

  var bridgeWS: BridgeWebSocket
  private var cancellables = Set<AnyCancellable>()
  private var messageObserver: AnyCancellable?
  private let notificationManager = NotificationManager.shared

  // Stuck detection
  private var lastActivityDate: Date = Date()
  private var stuckCheckTimer: Timer?
  private var stuckNotificationSent: Bool = false

  // Build failure tracking
  private var buildRetryCount: Int = 0
  private static let maxBuildRetries = 3

  // Token threshold tracking
  private var tokenThresholdNotified = Set<Int>()

  init(bridgeWS: BridgeWebSocket) {
    self.bridgeWS = bridgeWS
    observeConnection()
    setupNotificationActions()
  }

  // MARK: - Session Lifecycle

  func startSession(ticketID: String, project: String, criteria: [String] = []) {
    let session = AgentSession(ticketID: ticketID, project: project)
    session.criteria = criteria.map { AcceptanceCriterion(text: $0) }
    activeSession = session

    // Reset tracking state
    lastActivityDate = Date()
    stuckNotificationSent = false
    buildRetryCount = 0
    tokenThresholdNotified.removeAll()

    connectAsHuman()
    observeMessages()
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
    messageObserver?.cancel()
    messageObserver = nil
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
    bridgeWS.send(
      type: "human_approval",
      payload: "{\"approved\": true, \"request_id\": \"\(request.messageID)\"}")

    activeSession?.pendingApproval = nil
    activeSession?.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "Approved: \(request.description)",
        from: "human"
      ))
  }

  func denyRequest(_ request: ApprovalRequest) {
    bridgeWS.send(
      type: "human_approval",
      payload: "{\"approved\": false, \"request_id\": \"\(request.messageID)\"}")

    activeSession?.pendingApproval = nil
    activeSession?.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "Denied: \(request.description)",
        from: "human"
      ))
  }

  // MARK: - Notification Action Handling

  private func setupNotificationActions() {
    notificationManager.onActionReceived = { [weak self] action, context in
      DispatchQueue.main.async {
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
      // Bring app to foreground — already handled by NotificationManager
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Viewing logs from notification", from: "system"))

    case .retryBuild:
      buildRetryCount = 0
      sendCommand("/retry-build")
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Build retry triggered via notification", from: "human"))

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
      // Bring app to foreground — already handled by NotificationManager
      session.addFeedMessage(
        FeedMessage(type: .system, content: "Viewing diff from notification", from: "system"))

    case .pauseAgent:
      sendCommand("/pause")
      session.addFeedMessage(
        FeedMessage(
          type: .system, content: "Agent paused via notification (token threshold)", from: "human"))
    }
  }

  // MARK: - Stuck Detection

  private func startStuckDetection() {
    stopStuckDetection()
    stuckCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
      [weak self] _ in
      self?.checkIfStuck()
    }
  }

  private func stopStuckDetection() {
    stuckCheckTimer?.invalidate()
    stuckCheckTimer = nil
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

  // MARK: - Message Observation

  private func observeConnection() {
    bridgeWS.$isConnected
      .receive(on: DispatchQueue.main)
      .sink { [weak self] connected in
        self?.isConnectedAsHuman = connected
      }
      .store(in: &cancellables)
  }

  private func observeMessages() {
    messageObserver = bridgeWS.$messages
      .receive(on: DispatchQueue.main)
      .sink { [weak self] messages in
        self?.processNewMessages(messages)
      }
  }

  private var lastProcessedCount = 0

  private func processNewMessages(_ messages: [BridgeEnvelope]) {
    guard let session = activeSession else { return }
    guard messages.count > lastProcessedCount else { return }

    let newMessages = messages.suffix(from: lastProcessedCount)
    lastProcessedCount = messages.count

    for envelope in newMessages {
      processEnvelope(envelope, session: session)
    }
  }

  private func processEnvelope(_ envelope: BridgeEnvelope, session: AgentSession) {
    let payload = envelope.payload.stringValue

    // Record activity for stuck detection on any agent message
    if envelope.from == "agent" || envelope.from?.hasPrefix("agent") == true {
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
    // Expected format: JSON with "tokens_used" and "token_limit" fields
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

    // Also notify at higher milestones: 90%, 95%, 100%
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

    notificationManager.sendTicketCompletedNotification(
      ticketID: session.ticketID,
      project: session.project,
      criteriaCount: session.criteria.count
    )

    session.addFeedMessage(
      FeedMessage(
        type: .system,
        content: "All \(session.criteria.count) criteria met — ticket complete notification sent",
        from: "system"
      ))

    triggerHaptic()
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
        // Parse starting line number from @@ -X,Y +Z,W @@
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
      triggerHaptic()
    }
  }

  private func checkCriteriaCompletion(payload: String, session: AgentSession) {
    for i in session.criteria.indices where !session.criteria[i].isCompleted {
      if payload.localizedCaseInsensitiveContains(session.criteria[i].text) {
        session.criteria[i].isCompleted = true
        triggerHaptic()
      }
    }
  }

  // MARK: - Haptics

  private func triggerHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
  }
}
