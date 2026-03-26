import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
  case missionControl = "Mission Control"
  case codeReview = "Code Review"
  case queue = "Queue"
  case dashboard = "Dashboard"
  case providers = "Providers"
  case workload = "Workload"
  case assign = "Assign Ticket"
  case monitor = "Live Monitor"
  case performance = "Performance"
  case settings = "Settings"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .missionControl: return "antenna.radiowaves.left.and.right"
    case .codeReview: return "doc.text.magnifyingglass"
    case .queue: return "list.bullet.rectangle"
    case .dashboard: return "gauge.open.with.lines.needle.33percent"
    case .providers: return "cloud.fill"
    case .workload: return "square.grid.3x3.fill"
    case .assign: return "ticket"
    case .monitor: return "waveform"
    case .performance: return "chart.bar.fill"
    case .settings: return "gearshape"
    }
  }
}

struct ContentView: View {
  @Environment(AgentService.self) var agentService
  @State private var selection: SidebarItem = .missionControl
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  @State private var connectionManager = ConnectionManager()

  var body: some View {
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
      // The ConnectionSwitcher is always visible in toolbar
      // This notification could trigger a highlight or dropdown
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
