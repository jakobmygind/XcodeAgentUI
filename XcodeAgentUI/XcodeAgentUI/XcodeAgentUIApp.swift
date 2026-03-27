import SwiftUI
import XcodeAgentUICore
import XcodeAgentUIFeatures
import XcodeAgentUIAppShell

@main
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

      CommandMenu("Connection") {
        Button("Switch Connection") {
          NotificationCenter.default.post(name: .showConnectionSwitcher, object: nil)
        }
        .keyboardShortcut("K", modifiers: [.command, .shift])

        Button("Reconnect") {
          NotificationCenter.default.post(name: .reconnectConnection, object: nil)
        }
        .keyboardShortcut("R", modifiers: [.command, .shift])

        Button("Disconnect") {
          NotificationCenter.default.post(name: .disconnectConnection, object: nil)
        }
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
