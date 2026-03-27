import Observation
import Sharing
import SwiftUI

@Observable
public final class SmartDefaults: @unchecked Sendable {

  public nonisolated(unsafe) static let shared = SmartDefaults()

  // MARK: - Persisted State

  @ObservationIgnored @Shared(.appStorage("xar_hasCompletedOnboarding"))
  public var hasCompletedOnboarding = false

  @ObservationIgnored @Shared(.appStorage("xar_sessionCount"))
  public var sessionCount = 0

  @ObservationIgnored @Shared(.appStorage("xar_lastUsedProvider"))
  public var lastUsedProvider = ""

  @ObservationIgnored @Shared(.appStorage("xar_lastUsedModel"))
  public var lastUsedModel = "claude-sonnet-4-20250514"

  @ObservationIgnored @Shared(.appStorage("xar_preferredPriority"))
  public var preferredPriority = "medium"

  @ObservationIgnored @Shared(.appStorage("xar_lastProjectPath"))
  public var lastProjectPath = ""

  @ObservationIgnored @Shared(.appStorage("xar_sidebarFavorites"))
  public var sidebarFavoritesRaw = ""

  @ObservationIgnored @Shared(.appStorage("xar_navigationHistory"))
  public var navigationHistoryRaw = ""

  // MARK: - Live State

  public var suggestedAction: SuggestedAction?
  public var recentNavigations: [SidebarItem] = []

  // MARK: - Types

  public struct SuggestedAction: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let icon: String
    public let accent: Color
    public let action: @MainActor () -> Void
  }

  enum UserExperience {
    case firstTime
    case beginner
    case intermediate
    case powerUser

    var showTooltips: Bool {
      switch self {
      case .firstTime, .beginner: return true
      case .intermediate, .powerUser: return false
      }
    }

    var showCoachMarks: Bool { self == .firstTime }
    var showShortcutHints: Bool { self != .firstTime }
  }

  // MARK: - Computed

  var userExperience: UserExperience {
    switch sessionCount {
    case 0: return .firstTime
    case 1...5: return .beginner
    case 6...20: return .intermediate
    default: return .powerUser
    }
  }

  public var isPowerUser: Bool { sessionCount > 20 }

  public var frequentDestinations: [SidebarItem] {
    let history = navigationHistoryRaw
      .split(separator: ",")
      .compactMap { name in SidebarItem.allCases.first { $0.rawValue == String(name) } }

    var counts: [SidebarItem: Int] = [:]
    history.forEach { counts[$0, default: 0] += 1 }

    return counts.sorted { $0.value > $1.value }
      .prefix(3)
      .map(\.key)
  }

  // MARK: - Actions

  @MainActor
  public func recordNavigation(_ item: SidebarItem) {
    var history = navigationHistoryRaw
      .split(separator: ",")
      .map(String.init)
    history.append(item.rawValue)
    if history.count > 50 { history.removeFirst(history.count - 50) }
    $navigationHistoryRaw.withLock { $0 = history.joined(separator: ",") }

    recentNavigations.removeAll { $0 == item }
    recentNavigations.insert(item, at: 0)
    if recentNavigations.count > 5 { recentNavigations.removeLast() }
  }

  @MainActor
  public func recordSessionStart() {
    $sessionCount.withLock { $0 += 1 }
  }

  @MainActor
  public func completeOnboarding() {
    withAnimation(XARAnimation.smooth) {
      $hasCompletedOnboarding.withLock { $0 = true }
    }
  }

  @MainActor
  public func updateSuggestedAction(for service: AgentService) {
    let routerRunning = service.routerStatus.state == .running
    let bridgeRunning = service.bridgeStatus.state == .running
    let hasSession = service.sessionManager.activeSession != nil

    if !routerRunning && !bridgeRunning {
      suggestedAction = SuggestedAction(
        title: "Start Services",
        subtitle: "Router and Bridge are offline",
        icon: "power",
        accent: XARColors.electricEmerald
      ) {
        service.startAll()
      }
    } else if routerRunning && bridgeRunning && !hasSession {
      suggestedAction = SuggestedAction(
        title: "Start a Session",
        subtitle: "Services ready — assign a ticket",
        icon: "play.fill",
        accent: XARColors.electricCyan
      ) {
        NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.assign)
      }
    } else if hasSession {
      if let approval = service.sessionManager.activeSession?.pendingApproval {
        suggestedAction = SuggestedAction(
          title: "Review Pending Action",
          subtitle: approval.description,
          icon: "hand.raised.fill",
          accent: XARColors.electricAmber
        ) {
          service.sessionManager.approveRequest(approval)
        }
      } else {
        suggestedAction = nil
      }
    } else {
      suggestedAction = nil
    }
  }

  // MARK: - Keyboard Shortcut Descriptions

  public static let shortcuts: [(key: String, description: String, category: String)] = [
    ("⌘1", "Dashboard", "Navigate"),
    ("⌘2", "Mission Control", "Navigate"),
    ("⌘3", "Queue", "Navigate"),
    ("⌘0", "Toggle Sidebar", "Navigate"),
    ("⌘⏎", "Approve Pending Action", "Session"),
    ("⇧⌘W", "End Session", "Session"),
    ("⇧⌘N", "New Mission Control Window", "Window"),
  ]

  private init() {}
}
