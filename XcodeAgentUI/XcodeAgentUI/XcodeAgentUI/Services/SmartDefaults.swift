import SwiftUI
import Combine

// MARK: - Smart Defaults Service

/// Learns from user behavior to surface intelligent defaults and reduce friction.
/// Tracks navigation patterns, frequently used actions, and session preferences
/// to pre-fill forms, suggest next actions, and adapt the UI to the user's workflow.
final class SmartDefaults: ObservableObject {

    static let shared = SmartDefaults()

    // MARK: - Persisted State

    @AppStorage("xar.hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("xar.sessionCount") var sessionCount = 0
    @AppStorage("xar.lastUsedProvider") var lastUsedProvider = ""
    @AppStorage("xar.lastUsedModel") var lastUsedModel = "claude-sonnet-4-20250514"
    @AppStorage("xar.preferredPriority") var preferredPriority = "medium"
    @AppStorage("xar.lastProjectPath") var lastProjectPath = ""
    @AppStorage("xar.sidebarFavorites") private var sidebarFavoritesRaw = ""
    @AppStorage("xar.navigationHistory") private var navigationHistoryRaw = ""

    // MARK: - Live State

    @Published var suggestedAction: SuggestedAction?
    @Published var recentNavigations: [SidebarItem] = []

    // MARK: - Types

    struct SuggestedAction: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let accent: Color
        let action: () -> Void
    }

    enum UserExperience {
        case firstTime      // 0 sessions
        case beginner       // 1–5 sessions
        case intermediate   // 6–20 sessions
        case powerUser      // 20+ sessions

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

    var isPowerUser: Bool { sessionCount > 20 }

    var frequentDestinations: [SidebarItem] {
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

    func recordNavigation(_ item: SidebarItem) {
        // Keep rolling window of last 50 navigations
        var history = navigationHistoryRaw
            .split(separator: ",")
            .map(String.init)
        history.append(item.rawValue)
        if history.count > 50 { history.removeFirst(history.count - 50) }
        navigationHistoryRaw = history.joined(separator: ",")

        // Update recent
        recentNavigations.removeAll { $0 == item }
        recentNavigations.insert(item, at: 0)
        if recentNavigations.count > 5 { recentNavigations.removeLast() }
    }

    func recordSessionStart() {
        sessionCount += 1
    }

    func completeOnboarding() {
        withAnimation(XARAnimation.smooth) {
            hasCompletedOnboarding = true
        }
    }

    func updateSuggestedAction(for service: AgentService) {
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
                    subtitle: approval.message,
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

    static let shortcuts: [(key: String, description: String, category: String)] = [
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
