import Foundation

public enum SidebarItem: String, CaseIterable, Identifiable {
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

  public var id: String { rawValue }

  public var icon: String {
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

extension Notification.Name {
  public static let navigateTo = Notification.Name("navigateTo")
  public static let showConnectionSwitcher = Notification.Name("showConnectionSwitcher")
  public static let reconnectConnection = Notification.Name("reconnectConnection")
  public static let disconnectConnection = Notification.Name("disconnectConnection")
}
