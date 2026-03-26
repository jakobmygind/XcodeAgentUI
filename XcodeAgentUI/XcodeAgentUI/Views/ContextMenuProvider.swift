import SwiftUI

// MARK: - Context Menu Provider

/// Adds right-click context menus throughout the app with intelligent, contextual actions.
/// Menus adapt based on service state, active sessions, and user experience level.
///
/// ```swift
/// SidebarItem.missionControl.label
///   .sidebarContextMenu(item: .missionControl, agentService: agentService)
/// ```

// MARK: - Sidebar Context Menu

struct SidebarContextMenu: ViewModifier {
    let item: SidebarItem
    var agentService: AgentService
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.contextMenu {
            switch item {
            case .missionControl:
                missionControlMenu
            case .queue:
                queueMenu
            case .performance:
                performanceMenu
            case .settings:
                settingsMenu
            default:
                defaultMenu
            }
        }
    }

    // MARK: - Mission Control Menu

    @ViewBuilder
    private var missionControlMenu: some View {
        Button {
            openWindow(id: "mission-control")
        } label: {
            Label("Open in New Window", systemImage: "macwindow.badge.plus")
        }

        Divider()

        Group {
            if agentService.routerStatus.state == .running && agentService.bridgeStatus.state == .running {
                Button {
                    agentService.stopAll()
                } label: {
                    Label("Stop All Services", systemImage: "stop.fill")
                }
            } else {
                Button {
                    agentService.startAll()
                } label: {
                    Label("Start All Services", systemImage: "play.fill")
                }
            }
        }

        if let session = agentService.sessionManager.activeSession {
            Divider()

            if let approval = session.pendingApproval {
                Button {
                    agentService.sessionManager.approveRequest(approval)
                } label: {
                    Label("Approve Pending Action", systemImage: "checkmark.circle")
                }
            }

            Button(role: .destructive) {
                agentService.sessionManager.endSession()
            } label: {
                Label("End Session", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Queue Menu

    @ViewBuilder
    private var queueMenu: some View {
        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.assign)
        } label: {
            Label("New Ticket", systemImage: "plus.circle")
        }

        Divider()

        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.queue)
        } label: {
            Label("View Queue", systemImage: "list.bullet")
        }
    }

    // MARK: - Performance Menu

    @ViewBuilder
    private var performanceMenu: some View {
        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.performance)
        } label: {
            Label("View Metrics", systemImage: "chart.bar")
        }

        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.monitor)
        } label: {
            Label("Live Monitor", systemImage: "waveform")
        }
    }

    // MARK: - Settings Menu

    @ViewBuilder
    private var settingsMenu: some View {
        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.providers)
        } label: {
            Label("Manage Providers", systemImage: "cloud")
        }

        Button {
            NotificationCenter.default.post(name: .navigateTo, object: SidebarItem.settings)
        } label: {
            Label("Open Settings", systemImage: "gearshape")
        }
    }

    // MARK: - Default Menu

    @ViewBuilder
    private var defaultMenu: some View {
        Button {
            NotificationCenter.default.post(name: .navigateTo, object: item)
        } label: {
            Label("Open \(item.rawValue)", systemImage: item.icon)
        }
    }
}

// MARK: - Quick Actions Palette

/// Command-palette style overlay for power users — fast access to any action.
/// Triggered by a keyboard shortcut from the app menu.
struct QuickActionsPalette: View {
    @Environment(AgentService.self) var agentService
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var filteredActions: [QuickAction] {
        let all = buildActions()
        if searchText.isEmpty { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        if isPresented {
            ZStack {
                // Backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(XARColors.electricCyan)

                        TextField("Search actions...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundStyle(XARColors.textPrimary)
                            .focused($isFocused)
                            .onSubmit { executeSelected() }
                    }
                    .padding(16)

                    Rectangle()
                        .fill(XARColors.glassBorder)
                        .frame(height: 1)

                    // Results
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                                actionRow(action, isSelected: index == selectedIndex)
                                    .onTapGesture {
                                        selectedIndex = index
                                        executeSelected()
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 300)
                }
                .frame(width: 480)
                .glowingGlass(accent: XARColors.electricCyan, cornerRadius: 16, glowRadius: 30)
                .padding(.top, 80)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .onAppear {
                isFocused = true
                selectedIndex = 0
            }
            .onKeyPress(.upArrow) {
                selectedIndex = max(0, selectedIndex - 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                selectedIndex = min(filteredActions.count - 1, selectedIndex + 1)
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
    }

    private func actionRow(_ action: QuickAction, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(action.accent)
                .frame(width: 28, height: 28)
                .background(action.accent.opacity(isSelected ? 0.15 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(XARColors.textPrimary)

                Text(action.category)
                    .font(.system(size: 11))
                    .foregroundStyle(XARColors.textTertiary)
            }

            Spacer()

            if let shortcut = action.shortcut {
                ShortcutHint(shortcut)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? XARColors.electricCyan.opacity(0.1) : .clear)
        )
        .contentShape(Rectangle())
    }

    private func executeSelected() {
        guard selectedIndex < filteredActions.count else { return }
        filteredActions[selectedIndex].action()
        dismiss()
    }

    private func dismiss() {
        withAnimation(XARAnimation.fade) {
            isPresented = false
        }
        searchText = ""
    }

    // MARK: - Build Actions

    private func buildActions() -> [QuickAction] {
        var actions: [QuickAction] = []

        // Navigation
        for item in SidebarItem.allCases {
            let shortcutKey = SmartDefaults.shortcuts.first { $0.description == item.rawValue }?.key
            actions.append(QuickAction(
                title: item.rawValue,
                category: "Navigate",
                icon: item.icon,
                accent: XARColors.electricBlue,
                shortcut: shortcutKey
            ) {
                NotificationCenter.default.post(name: .navigateTo, object: item)
            })
        }

        // Services
        let allRunning = agentService.routerStatus.state == .running
            && agentService.bridgeStatus.state == .running

        if allRunning {
            actions.append(QuickAction(
                title: "Stop All Services", category: "Services",
                icon: "stop.fill", accent: XARColors.statusError
            ) { agentService.stopAll() })
        } else {
            actions.append(QuickAction(
                title: "Start All Services", category: "Services",
                icon: "play.fill", accent: XARColors.electricEmerald
            ) { agentService.startAll() })
        }

        // Session
        if let session = agentService.sessionManager.activeSession {
            if let approval = session.pendingApproval {
                actions.append(QuickAction(
                    title: "Approve Pending Action", category: "Session",
                    icon: "checkmark.circle.fill", accent: XARColors.electricAmber,
                    shortcut: "⌘⏎"
                ) { agentService.sessionManager.approveRequest(approval) })
            }

            actions.append(QuickAction(
                title: "End Session", category: "Session",
                icon: "xmark.circle", accent: XARColors.statusError,
                shortcut: "⇧⌘W"
            ) { agentService.sessionManager.endSession() })
        }

        return actions
    }
}

// MARK: - Quick Action Model

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let category: String
    let icon: String
    let accent: Color
    var shortcut: String? = nil
    let action: () -> Void
}

// MARK: - View Extensions

extension View {
    /// Attach a contextual right-click menu appropriate for the given sidebar item
    func sidebarContextMenu(item: SidebarItem, agentService: AgentService) -> some View {
        modifier(SidebarContextMenu(item: item, agentService: agentService))
    }
}

// MARK: - Preview

#Preview("Quick Actions Palette") {
    ZStack {
        XARColors.void.ignoresSafeArea()
        QuickActionsPalette(isPresented: .constant(true))
            .environment(AgentService())
    }
    .frame(width: 700, height: 500)
}
