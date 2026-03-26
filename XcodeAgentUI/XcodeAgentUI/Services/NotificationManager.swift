import AppKit
import Foundation
import Observation
import Sharing
import UserNotifications

enum NotificationCategory: String {
  case approval = "APPROVAL"
  case buildFailed = "BUILD_FAILED"
  case agentStuck = "AGENT_STUCK"
  case ticketCompleted = "TICKET_COMPLETED"
  case tokenThreshold = "TOKEN_THRESHOLD"
}

enum NotificationAction: String {
  case approve = "APPROVE_ACTION"
  case deny = "DENY_ACTION"
  case viewLogs = "VIEW_LOGS_ACTION"
  case retryBuild = "RETRY_BUILD_ACTION"
  case nudgeAgent = "NUDGE_AGENT_ACTION"
  case abortAgent = "ABORT_AGENT_ACTION"
  case viewDiff = "VIEW_DIFF_ACTION"
  case pauseAgent = "PAUSE_TOKEN_ACTION"
}

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  nonisolated(unsafe) static let shared = NotificationManager()

  // MARK: - Preferences (persisted via @Shared)

  @ObservationIgnored
  @Shared(.appStorage("notif_approval"))
  var approvalNotificationsEnabled = true

  @ObservationIgnored
  @Shared(.appStorage("notif_buildFailed"))
  var buildFailedNotificationsEnabled = true

  @ObservationIgnored
  @Shared(.appStorage("notif_agentStuck"))
  var agentStuckNotificationsEnabled = true

  @ObservationIgnored
  @Shared(.appStorage("notif_ticketCompleted"))
  var ticketCompletedNotificationsEnabled = true

  @ObservationIgnored
  @Shared(.appStorage("notif_tokenThreshold"))
  var tokenThresholdNotificationsEnabled = true

  @ObservationIgnored
  @Shared(.appStorage("notif_stuckTimeout"))
  var stuckTimeoutMinutes = 10

  @ObservationIgnored
  @Shared(.appStorage("notif_tokenThresholdPercent"))
  var tokenUsageThresholdPercent = 80

  @ObservationIgnored
  @Shared(.appStorage("notif_sound"))
  var soundEnabled = true

  var isAuthorized: Bool = false

  var onActionReceived: ((NotificationAction, String) -> Void)?

  var recentNotifications: [NotificationRecord] = []

  override private init() {
    super.init()
  }

  // MARK: - Setup

  func setup() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    registerCategories()
    requestAuthorization()
  }

  func requestAuthorization() {
    Task { @MainActor in
      let granted = try? await UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge])
      self.isAuthorized = granted ?? false
    }
  }

  private func registerCategories() {
    let center = UNUserNotificationCenter.current()

    let approveAction = UNNotificationAction(
      identifier: NotificationAction.approve.rawValue,
      title: "Approve",
      options: [.authenticationRequired]
    )
    let denyAction = UNNotificationAction(
      identifier: NotificationAction.deny.rawValue,
      title: "Deny",
      options: [.destructive]
    )
    let approvalCategory = UNNotificationCategory(
      identifier: NotificationCategory.approval.rawValue,
      actions: [approveAction, denyAction],
      intentIdentifiers: []
    )

    let viewLogsAction = UNNotificationAction(
      identifier: NotificationAction.viewLogs.rawValue,
      title: "View Logs",
      options: [.foreground]
    )
    let retryAction = UNNotificationAction(
      identifier: NotificationAction.retryBuild.rawValue,
      title: "Retry Build",
      options: []
    )
    let buildFailedCategory = UNNotificationCategory(
      identifier: NotificationCategory.buildFailed.rawValue,
      actions: [viewLogsAction, retryAction],
      intentIdentifiers: []
    )

    let nudgeAction = UNNotificationAction(
      identifier: NotificationAction.nudgeAgent.rawValue,
      title: "Nudge Agent",
      options: []
    )
    let abortAction = UNNotificationAction(
      identifier: NotificationAction.abortAgent.rawValue,
      title: "Abort",
      options: [.destructive]
    )
    let stuckCategory = UNNotificationCategory(
      identifier: NotificationCategory.agentStuck.rawValue,
      actions: [nudgeAction, abortAction],
      intentIdentifiers: []
    )

    let viewDiffAction = UNNotificationAction(
      identifier: NotificationAction.viewDiff.rawValue,
      title: "View Changes",
      options: [.foreground]
    )
    let completedCategory = UNNotificationCategory(
      identifier: NotificationCategory.ticketCompleted.rawValue,
      actions: [viewDiffAction],
      intentIdentifiers: []
    )

    let pauseAction = UNNotificationAction(
      identifier: NotificationAction.pauseAgent.rawValue,
      title: "Pause Agent",
      options: [.destructive]
    )
    let tokenCategory = UNNotificationCategory(
      identifier: NotificationCategory.tokenThreshold.rawValue,
      actions: [pauseAction],
      intentIdentifiers: []
    )

    center.setNotificationCategories([
      approvalCategory, buildFailedCategory, stuckCategory, completedCategory, tokenCategory,
    ])
  }

  // MARK: - Send Notifications

  func sendApprovalNotification(requestID: String, description: String) {
    guard approvalNotificationsEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = "🔔 Agent Needs Approval"
    content.subtitle = "Action required"
    content.body = description
    content.categoryIdentifier = NotificationCategory.approval.rawValue
    content.sound = soundEnabled ? .default : nil
    content.userInfo = ["requestID": requestID, "type": "approval"]
    content.threadIdentifier = "agent-approval"

    deliver(content: content, identifier: "approval-\(requestID)")
    recordNotification(title: content.title, body: description, category: .approval)
  }

  func sendBuildFailedNotification(ticketID: String, retryCount: Int, error: String) {
    guard buildFailedNotificationsEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = "🔴 Build Failed"
    content.subtitle = "Ticket: \(ticketID)"
    content.body = "Failed after \(retryCount) retries. \(error)"
    content.categoryIdentifier = NotificationCategory.buildFailed.rawValue
    content.sound = soundEnabled ? .defaultCritical : nil
    content.userInfo = ["ticketID": ticketID, "type": "buildFailed"]
    content.threadIdentifier = "agent-build"
    content.interruptionLevel = .timeSensitive

    deliver(
      content: content, identifier: "build-\(ticketID)-\(Date().timeIntervalSince1970)")
    recordNotification(title: content.title, body: content.body, category: .buildFailed)
  }

  func sendAgentStuckNotification(ticketID: String, lastActivity: Date) {
    guard agentStuckNotificationsEnabled else { return }

    let minutes = Int(-lastActivity.timeIntervalSinceNow / 60)

    let content = UNMutableNotificationContent()
    content.title = "⚠️ Agent Stuck"
    content.subtitle = "Ticket: \(ticketID)"
    content.body = "No progress for \(minutes) minutes. The agent may need intervention."
    content.categoryIdentifier = NotificationCategory.agentStuck.rawValue
    content.sound = soundEnabled ? .default : nil
    content.userInfo = ["ticketID": ticketID, "type": "agentStuck"]
    content.threadIdentifier = "agent-stuck"
    content.interruptionLevel = .timeSensitive

    deliver(content: content, identifier: "stuck-\(ticketID)")
    recordNotification(title: content.title, body: content.body, category: .agentStuck)
  }

  func sendTicketCompletedNotification(ticketID: String, project: String, criteriaCount: Int) {
    guard ticketCompletedNotificationsEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = "✅ Ticket Completed"
    content.subtitle = "\(project) / \(ticketID)"
    content.body = "All \(criteriaCount) acceptance criteria met. Ready for review."
    content.categoryIdentifier = NotificationCategory.ticketCompleted.rawValue
    content.sound = soundEnabled ? .default : nil
    content.userInfo = ["ticketID": ticketID, "type": "ticketCompleted"]
    content.threadIdentifier = "agent-completed"

    deliver(content: content, identifier: "completed-\(ticketID)")
    recordNotification(title: content.title, body: content.body, category: .ticketCompleted)
  }

  func sendTokenThresholdNotification(
    ticketID: String, tokensUsed: Int, tokenLimit: Int, percent: Int
  ) {
    guard tokenThresholdNotificationsEnabled else { return }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let usedStr = formatter.string(from: NSNumber(value: tokensUsed)) ?? "\(tokensUsed)"
    let limitStr = formatter.string(from: NSNumber(value: tokenLimit)) ?? "\(tokenLimit)"

    let content = UNMutableNotificationContent()
    content.title = "⚡ Token Usage High"
    content.subtitle = "Ticket: \(ticketID)"
    content.body =
      "\(percent)% of budget used (\(usedStr) / \(limitStr) tokens). Consider pausing."
    content.categoryIdentifier = NotificationCategory.tokenThreshold.rawValue
    content.sound = soundEnabled ? .default : nil
    content.userInfo = ["ticketID": ticketID, "type": "tokenThreshold", "percent": percent]
    content.threadIdentifier = "agent-tokens"
    content.interruptionLevel = .active

    deliver(content: content, identifier: "tokens-\(ticketID)-\(percent)")
    recordNotification(title: content.title, body: content.body, category: .tokenThreshold)
  }

  // MARK: - Delivery

  private func deliver(content: UNMutableNotificationContent, identifier: String) {
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: trigger
    )
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        print("[NotificationManager] Failed to deliver: \(error.localizedDescription)")
      }
    }
  }

  private func recordNotification(
    title: String, body: String, category: NotificationCategory
  ) {
    let record = NotificationRecord(title: title, body: body, category: category)
    recentNotifications.insert(record, at: 0)
    if recentNotifications.count > 50 {
      recentNotifications.removeLast()
    }
  }

  // MARK: - Clear

  func clearAllDelivered() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    recentNotifications.removeAll()
  }

  func clearStuckNotification(ticketID: String) {
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: ["stuck-\(ticketID)"])
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
      Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let actionID = response.actionIdentifier
    let userInfo = response.notification.request.content.userInfo
    let requestID = userInfo["requestID"] as? String ?? ""
    let ticketID = userInfo["ticketID"] as? String ?? ""

    Task { @MainActor in
      NSApplication.shared.activate(ignoringOtherApps: true)

      if let action = NotificationAction(rawValue: actionID) {
        let context = requestID.isEmpty ? ticketID : requestID
        self.onActionReceived?(action, context)
      }
    }

    completionHandler()
  }
}

// MARK: - Notification Record

struct NotificationRecord: Identifiable {
  let id = UUID()
  let title: String
  let body: String
  let category: NotificationCategory
  let timestamp: Date

  init(
    title: String, body: String, category: NotificationCategory, timestamp: Date = Date()
  ) {
    self.title = title
    self.body = body
    self.category = category
    self.timestamp = timestamp
  }

  var categoryIcon: String {
    switch category {
    case .approval: return "hand.raised.fill"
    case .buildFailed: return "xmark.octagon.fill"
    case .agentStuck: return "exclamationmark.triangle.fill"
    case .ticketCompleted: return "checkmark.seal.fill"
    case .tokenThreshold: return "bolt.fill"
    }
  }

  var categoryColor: String {
    switch category {
    case .approval: return "orange"
    case .buildFailed: return "red"
    case .agentStuck: return "yellow"
    case .ticketCompleted: return "green"
    case .tokenThreshold: return "purple"
    }
  }
}
