import SwiftUI
import UserNotifications

/// Main Mission Control view: 4-panel layout for interactive agent sessions
struct MissionControlView: View {
  @Environment(AgentService.self) var agentService
  @State private var showStartSheet = false
  @State private var ticketID = ""
  @State private var project = ""
  @State private var criteriaText = ""
  @State private var selectedProvider: Provider?
  @State private var selectedModel: AgentModel = .opus

  private var sessionManager: SessionManager {
    agentService.sessionManager
  }

  var body: some View {
    VStack(spacing: 0) {
      if let session = sessionManager.activeSession {
        sessionLayout(session)
      } else {
        noSessionView
      }
    }
    .onAppear {
      requestNotificationPermission()
    }
    .sheet(isPresented: $showStartSheet) {
      StartSessionView(
        selectedProvider: $selectedProvider,
        project: $project,
        ticketID: $ticketID,
        selectedModel: $selectedModel,
        criteriaText: $criteriaText,
        onStart: startSession
      )
      .environment(agentService)
    }
  }

  // MARK: - Active Session Layout

  @ViewBuilder
  private func sessionLayout(_ session: AgentSession) -> some View {
    sessionHeader(session)

    HSplitView {
      DiffStreamView(session: session)
        .frame(minWidth: 350)

      VSplitView {
        AcceptanceCriteriaView(session: session)
          .frame(minHeight: 150)

        AgentFeedView(
          session: session,
          onApprove: { sessionManager.approveRequest($0) },
          onDeny: { sessionManager.denyRequest($0) }
        )
        .frame(minHeight: 200)
      }
      .frame(minWidth: 350)
    }

    Divider()

    SteeringBarView(
      isConnected: sessionManager.isConnectedAsHuman,
      onSend: { sessionManager.sendCommand($0) }
    )
  }

  // MARK: - Session Header

  private func sessionHeader(_ session: AgentSession) -> some View {
    HStack(spacing: 12) {
      HStack(spacing: 6) {
        Circle()
          .fill(sessionManager.isConnectedAsHuman ? Color.green : Color.red)
          .frame(width: 10, height: 10)
        Text(sessionManager.isConnectedAsHuman ? "LIVE" : "DISCONNECTED")
          .font(.caption)
          .fontWeight(.bold)
          .foregroundColor(sessionManager.isConnectedAsHuman ? .green : .red)
      }

      Divider().frame(height: 16)

      Label(session.ticketID, systemImage: "ticket")
        .font(.callout)
        .fontWeight(.medium)

      Text(session.project)
        .font(.caption)
        .foregroundColor(.secondary)

      Divider().frame(height: 16)

      Text(session.startedAt, style: .relative)
        .font(.caption)
        .foregroundColor(.secondary)

      Spacer()

      if !sessionManager.isConnectedAsHuman {
        Button("Reconnect") {
          sessionManager.connectAsHuman()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

      Button("End Session") {
        sessionManager.endSession()
      }
      .buttonStyle(.bordered)
      .tint(.red)
      .controlSize(.small)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.bar)
  }

  // MARK: - No Session View

  private var noSessionView: some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "antenna.radiowaves.left.and.right")
        .font(.system(size: 48))
        .foregroundColor(.accentColor)

      Text("Mission Control")
        .font(.largeTitle)
        .fontWeight(.bold)

      Text(
        "Start an interactive agent session to monitor diffs,\ntrack acceptance criteria, and steer the agent in real time."
      )
      .font(.body)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)

      // Connected providers summary
      connectedProvidersSummary

      Button(action: { prepareStartSheet() }) {
        Label("Start Session", systemImage: "play.fill")
          .font(.headline)
          .padding(.horizontal, 24)
          .padding(.vertical, 10)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(agentService.providerStore.connectedProviders.isEmpty)

      if agentService.bridgeStatus.state != .running {
        Label(
          "Bridge is not running — start it from Dashboard first",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundColor(.orange)
      }

      if agentService.providerStore.connectedProviders.isEmpty {
        Label(
          "No providers connected — add credentials in Settings",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundColor(.orange)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Connected Providers Summary

  private var connectedProvidersSummary: some View {
    let connected = agentService.providerStore.connectedProviders
    return Group {
      if !connected.isEmpty {
        HStack(spacing: 8) {
          ForEach(connected) { provider in
            HStack(spacing: 4) {
              Image(systemName: provider.type.icon)
                .font(.caption)
              Text(provider.name)
                .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .foregroundColor(.green)
            .clipShape(Capsule())
          }
        }
      }
    }
  }

  // MARK: - Start Session Sheet

  private func prepareStartSheet() {
    let connected = agentService.providerStore.connectedProviders
    selectedProvider = connected.first
    if let provider = selectedProvider {
      project = provider.defaultProject
    }
    showStartSheet = true
  }

  private func startSession() {
    let criteria =
      criteriaText
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    sessionManager.startSession(
      ticketID: ticketID,
      project: project,
      criteria: criteria
    )
    showStartSheet = false
    ticketID = ""
    project = ""
    criteriaText = ""
  }

  // MARK: - Notifications

  private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }
}
