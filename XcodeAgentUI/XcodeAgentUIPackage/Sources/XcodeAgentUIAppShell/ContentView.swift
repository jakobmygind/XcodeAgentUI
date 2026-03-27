import SwiftUI
import XcodeAgentUICore
import XcodeAgentUIFeatures

public struct ContentView: View {
  @Environment(AgentService.self) var agentService
  @State private var selection: SidebarItem = .missionControl
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @State private var connectionManager = ConnectionManager()

  public init() {}

  public var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(SidebarItem.allCases, selection: $selection) { item in
        Label(item.rawValue, systemImage: item.icon)
          .tag(item)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 180)
      .listStyle(.sidebar)
    } detail: {
      switch selection {
      case .missionControl:
        MissionControlView()
      case .codeReview:
        DiffReviewView()
      case .queue:
        QueueView()
      case .dashboard:
        DashboardView()
      case .providers:
        ProviderManagementView()
      case .workload:
        WorkloadView()
      case .assign:
        TicketAssignView()
      case .monitor:
        LiveMonitorView()
      case .performance:
        PerformanceView(metricsStore: agentService.metricsStore)
      case .settings:
        SettingsView()
      }
    }
    .navigationTitle("Xcode Agent Runner")
    .toolbar {
      ToolbarItem(placement: .status) {
        ConnectionSwitcher(connectionManager: connectionManager)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .navigateTo)) { notification in
      if let item = notification.object as? SidebarItem {
        selection = item
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .showConnectionSwitcher)) { _ in
    }
    .onReceive(NotificationCenter.default.publisher(for: .reconnectConnection)) { _ in
      Task {
        await connectionManager.reconnect()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .disconnectConnection)) { _ in
      connectionManager.disconnect()
    }
    .task {
      await connectionManager.loadProfiles()
    }
  }
}
