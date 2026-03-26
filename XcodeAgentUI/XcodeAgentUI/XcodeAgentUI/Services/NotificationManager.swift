import AppKit
import Combine
import Foundation
import UserNotifications

/// Defines the categories and actions for actionable notifications
enum NotificationCategory: String {
  case approval = "APPROVAL"
  case buildFailed = "BUILD_FAILED"
  case agentStuck = "AGENT_STUCK"
  case ticketCompleted = "TICKET_COMPLETED"
  case tokenThreshold = "TOKEN_THRESHOLD"
}

enum NotificationAction: String {
  // Approval actions
  case approve = "APPROVE_ACTION"
  case deny = "DENY_ACTION"

  // Build failed actions
  case viewLogs = "VIEW_LOGS_ACTION"
  case retryBuild = "RETRY_BUILD_ACTION"

  // Agent stuck actions
  case nudgeAgent = "NUDGE_AGENT_ACTION"
  case abortAgent = "ABORT_AGENT_ACTION"

  // Ticket completed actions
  case viewDiff = "VIEW_DIFF_ACTION"

  // Token threshold actions
  case pauseAgent = "PAUSE_TOKEN_ACTION"
}

/// Manages macOS notification center integration with actionable notifications
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationManager()

  // MARK: - Preferences (persisted to UserDefaults)

  @Published var approvalNotificationsEnabled: Bool {
    didSet { UserDefaults.standard.set(approvalNotificationsEnabled, forKey: "notif.approval") }
  }
  @Published var buildFailedNotificationsEnabled: Bool {
    didSet { UserDefaults.standard.set(buildFailedNotificationsEnabled, forKey: "notif.buildFailed") }
  }
  @Published var agentStuckNotificationsEnabled: Bool {
    didSet { UserDefaults.standard.set(agentStuckNotificationsEnabled, forKey: "notif.agentStuck") }
  }
  @Published var ticketCompletedNotificationsEnabled: Bool {
    didSet {
      UserDefaults.standard.set(ticketCompletedNotificationsEnabled, forKey: "notif.ticketCompleted")
    }
  }
  @Published var tokenThresholdNotificationsEnabled: Bool {
    didSet {
      UserDefaults.standard.set(tokenThresholdNotificationsEnabled, forKey: "notif.tokenThreshold")
    }
  }

  @Published var stuckTimeoutMinutes: Int {
    didSet { UserDefaults.standard.set(stuckTimeoutMinutes, forKey: "notif.stuckTimeout") }
  }
  @Published var tokenUsageThresholdPercent: Int {
    didSet { UserDefaults.standard.set(tokenUsageThresholdPercent, forKey: "notif.tokenThreshold%") }
  }
  @Published var soundEnabled: Bool {
    didSet { UserDefaults.standard.set(soundEnabled, forKey: "notif.sound") }
  }

  @Published var isAuthorized: Bool = false

  /// Callback for handling notification actions back in SessionManager
  var onActionReceived: ((NotificationAction, String) -> Void)?

  /// History of delivered notifications for the notification log
  @Published var recentNotifications: [NotificationRecord] = []

  override private init() {
    self.approvalNotificationsEnabled = UserDefaults.standard.object(forKey: "notif.approval") as? Bool
      ?? true
    self.buildFailedNotificationsEnabled =
      UserDefaults.standard.object(forKey: "notif.buildFailed") as? Bool ?? true
    self.agentStuckNotificationsEnabled =
      UserDefaults.standard.object(forKey: "notif.agentStuck") as? Bool ?? true
    self.ticketCompletedNotificationsEnabled =
      UserDefaults.standard.object(forKey: "notif.ticketCompleted") as? Bool ?? true
    self.tokenThresholdNotificationsEnabled =
      UserDefaults.standard.object(forKey: "notif.tokenThreshold") as? Bool ?? true
    self.stuckTimeoutMinutes = UserDefaults.standard.object(forKey: "notif.stuckTimeout") as? Int
      ?? 10
    self.tokenUsageThresholdPercent =
      UserDefaults.standard.object(forKey: "notif.tokenThreshold%") as? Int ?? 80
    self.soundEnabled = UserDefaults.standard.object(forKey: "notif.sound") as? Bool ?? true

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
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      [weak self] granted, _ in
      DispatchQueue.main.async {
        self?.isAuthorized = granted
      }
    }
  }

  private func registerCategories() {
    let center = UNUserNotificationCenter.current()

    // Approval: Approve / Deny
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

    // Build Failed: View Logs / Retry
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

    // Agent Stuck: Nudge / Abort
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

    // Ticket Completed: View Diff
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

    // Token Threshold: Pause Agent
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

    deliver(content: content, identifier: "build-\(ticketID)-\(Date().timeIntervalSince1970)")
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
    content.sound = soundEnabled ? UNNotificationSound(named: UNNotificationSoundName("complete")) : nil
    content.userInfo = ["ticketID": ticketID, "type": "ticketCompleted"]
    content.threadIdentifier = "agent-completed"

    // Fall back to default sound if custom not found
    if content.sound == nil && soundEnabled {
      content.sound = .default
    }

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
    content.body = "\(percent)% of budget used (\(usedStr) / \(limitStr) tokens). Consider pausing."
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

  private func recordNotification(title: String, body: String, category: NotificationCategory) {
    let record = NotificationRecord(title: title, body: body, category: category)
    DispatchQueue.main.async {
      self.recentNotifications.insert(record, at: 0)
      if self.recentNotifications.count > 50 {
        self.recentNotifications.removeLast()
      }
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

  /// Handle notifications when app is in foreground — show them as banners
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }

  /// Handle action button taps from notifications
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let actionID = response.actionIdentifier
    let userInfo = response.notification.request.content.userInfo
    let requestID = userInfo["requestID"] as? String ?? ""
    let ticketID = userInfo["ticketID"] as? String ?? ""

    // Bring app to front
    NSApplication.shared.activate(ignoringOtherApps: true)

    if let action = NotificationAction(rawValue: actionID) {
      let context = requestID.isEmpty ? ticketID : requestID
      onActionReceived?(action, context)
    } else if actionID == UNNotificationDefaultActionIdentifier {
      // User tapped the notification body — bring app to front (already done above)
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

  init(title: String, body: String, category: NotificationCategory, timestamp: Date = Date()) {
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
