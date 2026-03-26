import SwiftUI

#if !SPM_BUILD
@main
#endif
struct XcodeAgentUIApp: App {
  @State private var agentService = AgentService()

  init() {
    NotificationManager.shared.setup()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(agentService)
        .frame(minWidth: 900, minHeight: 600)
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 1100, height: 750)
    .commands {
      CommandGroup(after: .newItem) {
        OpenMissionControlButton()
      }

      CommandMenu("Session") {
        Button("Approve Pending Action") {
          if let approval = agentService.sessionManager.activeSession?.pendingApproval {
            agentService.sessionManager.approveRequest(approval)
          }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(agentService.sessionManager.activeSession?.pendingApproval == nil)

        Button("End Session") {
          agentService.sessionManager.endSession()
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])
        .disabled(agentService.sessionManager.activeSession == nil)
      }

      CommandMenu("Navigate") {
        Button("Dashboard") {
          NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.dashboard)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Mission Control") {
          NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.missionControl)
        }
        .keyboardShortcut("2", modifiers: .command)

        Button("Queue") {
          NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.queue)
        }
        .keyboardShortcut("3", modifiers: .command)

        Divider()

        Button("Toggle Sidebar") {
          NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        }
        .keyboardShortcut("0", modifiers: .command)
      }
    }

    WindowGroup("Mission Control", id: "mission-control") {
      MissionControlView()
        .environment(agentService)
        .frame(minWidth: 700, minHeight: 500)
    }
    .defaultSize(width: 1000, height: 700)

    Settings {
      SettingsView()
        .environment(agentService)
    }

    MenuBarExtra {
      MenuBarView()
        .environment(agentService)
    } label: {
      MenuBarStatusIcon(agentService: agentService)
    }
  }

}

// MARK: - Open Mission Control Button (uses @Environment)

struct OpenMissionControlButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("New Mission Control Window") {
      openWindow(id: "mission-control")
    }
    .keyboardShortcut("N", modifiers: [.command, .shift])
  }
}

// MARK: - Navigation Notification

extension Notification.Name {
  static let navigateTo = Notification.Name("navigateTo")
}

// MARK: - Menu Bar Status Icon

struct MenuBarStatusIcon: View {
  var agentService: AgentService

  var body: some View {
    Image(systemName: statusSymbol)
  }

  /// Uses distinct SF Symbols since MenuBarExtra renders labels as template images
  /// (foregroundColor is ignored — the system applies monochrome tinting).
  private var statusSymbol: String {
    let routerRunning = agentService.routerStatus.state == .running
    let bridgeRunning = agentService.bridgeStatus.state == .running
    let hasSession = agentService.sessionManager.activeSession != nil

    if routerRunning && bridgeRunning {
      return hasSession ? "antenna.radiowaves.left.and.right" : "checkmark.circle"
    } else if routerRunning || bridgeRunning {
      return "exclamationmark.triangle"
    } else {
      return "xmark.circle"
    }
  }
}

// MARK: - Menu Bar Quick Actions

struct MenuBarView: View {
  @Environment(AgentService.self) var agentService

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Status section
      Label {
        Text("Router: \(agentService.routerStatus.state.rawValue.capitalized)")
      } icon: {
        Circle()
          .fill(agentService.routerStatus.state == .running ? Color.green : Color.red)
          .frame(width: 8, height: 8)
      }

      Label {
        Text("Bridge: \(agentService.bridgeStatus.state.rawValue.capitalized)")
      } icon: {
        Circle()
          .fill(agentService.bridgeStatus.state == .running ? Color.green : Color.red)
          .frame(width: 8, height: 8)
      }

      if let session = agentService.sessionManager.activeSession {
        Label("Session: \(session.ticketID)", systemImage: "antenna.radiowaves.left.and.right")
      }

      Divider()

      // Quick actions
      if agentService.routerStatus.state != .running {
        Button("Start Router") {
          agentService.startRouter()
        }
      }

      if agentService.routerStatus.state == .running && agentService.bridgeStatus.state == .running {
        Button("Stop All") {
          agentService.stopAll()
        }
      } else if agentService.routerStatus.state != .running
        && agentService.bridgeStatus.state != .running
      {
        Button("Start All") {
          agentService.startAll()
        }
      }

      Divider()

      Button("Open Xcode Agent Runner") {
        NSApp.activate()
      }

      Button("Quit") {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
