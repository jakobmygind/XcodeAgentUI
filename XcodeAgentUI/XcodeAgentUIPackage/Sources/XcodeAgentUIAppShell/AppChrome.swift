import SwiftUI
import AppKit
import XcodeAgentUICore
import XcodeAgentUIFeatures

public struct OpenMissionControlButton: View {
  @Environment(\.openWindow) private var openWindow

  public init() {}

  public var body: some View {
    Button("New Mission Control Window") {
      openWindow(id: "mission-control")
    }
    .keyboardShortcut("N", modifiers: [.command, .shift])
  }
}

public struct MenuBarStatusIcon: View {
  public var agentService: AgentService

  public init(agentService: AgentService) {
    self.agentService = agentService
  }

  public var body: some View {
    Image(systemName: statusSymbol)
  }

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

public struct MenuBarView: View {
  @Environment(AgentService.self) var agentService

  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
