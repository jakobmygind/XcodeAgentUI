import Sharing
import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
  var notificationManager = NotificationManager.shared

  var body: some View {
    Form {
      Section("Status") {
        HStack {
          Image(
            systemName: notificationManager.isAuthorized
              ? "bell.badge.fill" : "bell.slash.fill"
          )
          .foregroundStyle(notificationManager.isAuthorized ? .green : .red)
          .font(.title3)

          VStack(alignment: .leading, spacing: 2) {
            Text(
              notificationManager.isAuthorized
                ? "Notifications Enabled" : "Notifications Disabled"
            )
            .font(.headline)

            Text(
              notificationManager.isAuthorized
                ? "Smart notifications are active."
                : "Grant permission in System Settings > Notifications."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          Spacer()

          if !notificationManager.isAuthorized {
            Button("Request Permission") {
              notificationManager.requestAuthorization()
            }
            .controlSize(.small)
          }
        }
      }

      Section("Notification Types") {
        NotificationToggleRow(
          icon: "hand.raised.fill",
          color: .orange,
          title: "Agent Needs Approval",
          description: "Inline approve/deny from notification",
          isOn: Binding(notificationManager.$approvalNotificationsEnabled)
        )

        NotificationToggleRow(
          icon: "xmark.octagon.fill",
          color: .red,
          title: "Build Failed",
          description: "After retries exhausted, needs human intervention",
          isOn: Binding(notificationManager.$buildFailedNotificationsEnabled)
        )

        NotificationToggleRow(
          icon: "exclamationmark.triangle.fill",
          color: .yellow,
          title: "Agent Stuck",
          description: "No progress detected within timeout",
          isOn: Binding(notificationManager.$agentStuckNotificationsEnabled)
        )

        NotificationToggleRow(
          icon: "checkmark.seal.fill",
          color: .green,
          title: "Ticket Completed",
          description: "High-priority ticket finished with all criteria met",
          isOn: Binding(notificationManager.$ticketCompletedNotificationsEnabled)
        )

        NotificationToggleRow(
          icon: "bolt.fill",
          color: .purple,
          title: "Token Usage Threshold",
          description: "Budget consumption exceeds configured limit",
          isOn: Binding(notificationManager.$tokenThresholdNotificationsEnabled)
        )
      }

      Section("Thresholds") {
        HStack {
          Text("Stuck timeout")
          Spacer()
          Picker("", selection: Binding(notificationManager.$stuckTimeoutMinutes)) {
            Text("5 min").tag(5)
            Text("10 min").tag(10)
            Text("15 min").tag(15)
            Text("20 min").tag(20)
            Text("30 min").tag(30)
          }
          .pickerStyle(.menu)
          .frame(width: 120)
        }

        HStack {
          Text("Token usage alert at")
          Spacer()
          Picker("", selection: Binding(notificationManager.$tokenUsageThresholdPercent)) {
            Text("50%").tag(50)
            Text("60%").tag(60)
            Text("70%").tag(70)
            Text("80%").tag(80)
            Text("90%").tag(90)
            Text("95%").tag(95)
          }
          .pickerStyle(.menu)
          .frame(width: 120)
        }
      }

      Section("Sound") {
        Toggle("Play notification sound", isOn: Binding(notificationManager.$soundEnabled))
      }

      Section("Recent Notifications") {
        if notificationManager.recentNotifications.isEmpty {
          Text("No notifications sent yet.")
            .foregroundStyle(.secondary)
            .font(.caption)
        } else {
          VStack(spacing: 0) {
            ForEach(notificationManager.recentNotifications.prefix(10)) { record in
              NotificationRecordRow(record: record)
              if record.id != notificationManager.recentNotifications.prefix(10).last?.id {
                Divider()
              }
            }
          }

          HStack {
            Spacer()
            Button("Clear History") {
              notificationManager.clearAllDelivered()
            }
            .controlSize(.small)
            .foregroundStyle(.red)
          }
          .padding(.top, 4)
        }
      }
    }
    .padding()
    .task {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      notificationManager.isAuthorized = settings.authorizationStatus == .authorized
    }
  }
}

// MARK: - Toggle Row

struct NotificationToggleRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .foregroundStyle(color)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.body)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .toggleStyle(.switch)
  }
}

// MARK: - Record Row

struct NotificationRecordRow: View {
  let record: NotificationRecord

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: record.categoryIcon)
        .foregroundStyle(colorForCategory)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 1) {
        Text(record.title)
          .font(.caption)
          .fontWeight(.medium)
        Text(record.body)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Text(Self.timeFormatter.string(from: record.timestamp))
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 3)
  }

  private var colorForCategory: Color {
    switch record.category {
    case .approval: return .orange
    case .buildFailed: return .red
    case .agentStuck: return .yellow
    case .ticketCompleted: return .green
    case .tokenThreshold: return .purple
    }
  }
}
