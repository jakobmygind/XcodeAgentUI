import SwiftUI

// MARK: - Activity Status Bar

/// Persistent status strip at the bottom of the detail view.
/// Shows current system state, active session progress, and suggested next action.
/// Always visible — the user should never wonder "what's happening?"
struct ActivityStatusBar: View {
    @Environment(AgentService.self) var agentService
    var defaults = SmartDefaults.shared

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            // Service status cluster
            serviceCluster

            divider

            // Session status
            sessionStatus

            Spacer()

            // Suggested action (contextual)
            if let suggestion = defaults.suggestedAction {
                suggestedActionButton(suggestion)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 40)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.8)
                Rectangle().fill(XARColors.surface.opacity(0.5))
                // Top border glow
                VStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [statusAccent.opacity(0.3), statusAccent.opacity(0.05), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                    Spacer()
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(XARAnimation.smooth.delay(0.2)) {
                appeared = true
            }
            defaults.updateSuggestedAction(for: agentService)
        }
        .onChange(of: agentService.routerStatus.state) { _, _ in
            defaults.updateSuggestedAction(for: agentService)
        }
        .onChange(of: agentService.bridgeStatus.state) { _, _ in
            defaults.updateSuggestedAction(for: agentService)
        }
    }

    // MARK: - Service Status Cluster

    private var serviceCluster: some View {
        HStack(spacing: 10) {
            serviceChip("Router", state: agentService.routerStatus.state)
            serviceChip("Bridge", state: agentService.bridgeStatus.state)
        }
    }

    private func serviceChip(_ name: String, state: ServiceState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(colorForState(state))
                .frame(width: 6, height: 6)
                .if(state == .running) { $0.glowPulse(color: XARColors.statusOnline, intensity: 0.5) }

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(XARColors.textSecondary)
        }
    }

    // MARK: - Session Status

    @ViewBuilder
    private var sessionStatus: some View {
        if let session = agentService.sessionManager.activeSession {
            HStack(spacing: 8) {
                // Animated activity indicator
                ActivityPulse(color: XARColors.electricCyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.ticketID)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(XARColors.textPrimary)

                    Text(sessionPhaseLabel(session))
                        .font(.system(size: 10))
                        .foregroundStyle(XARColors.textTertiary)
                }

                // Progress ring if applicable
                if session.pendingApproval != nil {
                    PendingBadge()
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 11))
                    .foregroundStyle(XARColors.textTertiary)
                Text("No active session")
                    .font(.system(size: 11))
                    .foregroundStyle(XARColors.textTertiary)
            }
        }
    }

    // MARK: - Suggested Action Button

    private func suggestedActionButton(_ suggestion: SmartDefaults.SuggestedAction) -> some View {
        Button(action: suggestion.action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(suggestion.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(suggestion.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(suggestion.accent.opacity(0.12))
                Capsule().strokeBorder(suggestion.accent.opacity(0.25), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(XARColors.glassBorder)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 12)
    }

    private var statusAccent: Color {
        let allRunning = agentService.routerStatus.state == .running
            && agentService.bridgeStatus.state == .running
        return allRunning ? XARColors.electricCyan : XARColors.statusIdle
    }

    private func colorForState(_ state: ServiceState) -> Color {
        switch state {
        case .running: return XARColors.statusOnline
        case .starting: return XARColors.statusWarning
        case .stopped: return XARColors.statusIdle
        case .error: return XARColors.statusError
        }
    }

    private func sessionPhaseLabel(_ session: AgentSession) -> String {
        if session.pendingApproval != nil { return "Awaiting approval" }
        if session.feedMessages.isEmpty { return "Starting..." }
        return "Working"
    }
}

// MARK: - Activity Pulse

/// Animated dot that conveys "something is happening" — used in the status bar.
struct ActivityPulse: View {
    let color: Color
    @State private var scale: CGFloat = 0.6

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 16, height: 16)
                .scaleEffect(scale)

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.0
            }
        }
    }
}

// MARK: - Pending Approval Badge

/// Glowing amber badge that pulses to draw attention to a required action.
struct PendingBadge: View {
    @State private var glowing = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 9, weight: .bold))
            Text("ACTION")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(XARColors.electricAmber)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(XARColors.electricAmber.opacity(0.15))
            Capsule()
                .strokeBorder(XARColors.electricAmber.opacity(glowing ? 0.6 : 0.2), lineWidth: 1)
        }
        .shadow(color: XARColors.electricAmber.opacity(glowing ? 0.3 : 0.1), radius: 6)
        .onAppear {
            withAnimation(XARAnimation.pulse) {
                glowing = true
            }
        }
    }
}

// MARK: - Toast Notification

/// Temporary feedback message that slides in from the top.
/// Use for confirming actions: "Session started", "Agent approved", etc.
struct XARToast: View {
    let message: String
    let icon: String
    let accent: Color

    @State private var visible = true

    init(_ message: String, icon: String = "checkmark.circle.fill", accent: Color = XARColors.electricEmerald) {
        self.message = message
        self.icon = icon
        self.accent = accent
    }

    var body: some View {
        if visible {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(XARColors.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glowingGlass(accent: accent, cornerRadius: 12, glowRadius: 15)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(XARAnimation.smooth) {
                        visible = false
                    }
                }
            }
        }
    }
}

// MARK: - Progress Ring

/// Circular progress indicator with gradient stroke — for session/task progress.
struct ProgressRing: View {
    let progress: Double
    let accent: Color
    let size: CGFloat
    let lineWidth: CGFloat

    init(progress: Double, accent: Color = XARColors.electricCyan, size: CGFloat = 40, lineWidth: CGFloat = 4) {
        self.progress = progress
        self.accent = accent
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(XARColors.surfaceOverlay, lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.3), accent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * progress)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(XARAnimation.smooth, value: progress)

            // Percentage
            if size >= 36 {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .foregroundStyle(XARColors.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Activity Status Bar") {
    VStack {
        Spacer()
        ActivityStatusBar()
            .environment(AgentService())
    }
    .frame(width: 800, height: 100)
    .background(XARColors.void)
}

#Preview("Feedback Components") {
    VStack(spacing: 32) {
        XARToast("Session started successfully")
        XARToast("Agent needs approval", icon: "hand.raised.fill", accent: XARColors.electricAmber)

        HStack(spacing: 20) {
            ProgressRing(progress: 0.35)
            ProgressRing(progress: 0.72, accent: XARColors.electricViolet, size: 56)
            ProgressRing(progress: 1.0, accent: XARColors.electricEmerald, size: 32, lineWidth: 3)
        }

        HStack(spacing: 16) {
            ActivityPulse(color: XARColors.electricCyan)
            PendingBadge()
        }
    }
    .padding(40)
    .frame(width: 600, height: 400)
    .background(XARColors.void)
}
