import SwiftUI
import XcodeAgentUICore

// MARK: - Onboarding Overlay

/// Full-screen first-run experience with progressive coach marks.
/// Guides the user through the core workflow: Services → Session → Monitor.
/// Uses glassmorphism cards with staggered entrance animations.
///
/// Automatically shown when `SmartDefaults.hasCompletedOnboarding` is false.
struct OnboardingOverlay: View {
    @Environment(AgentService.self) var agentService
    var defaults = SmartDefaults.shared
    @State private var currentStep = 0
    @State private var dismissed = false

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to Xcode Agent Runner",
            subtitle: "Your AI-powered development command center",
            description: "XAR orchestrates coding agents, manages queues, and monitors performance — all from one elegant interface.",
            icon: "antenna.radiowaves.left.and.right",
            accent: XARColors.electricViolet,
            gradient: XARGradients.heroGlow
        ),
        OnboardingStep(
            title: "Start Your Backend",
            subtitle: "One backend, two endpoints",
            description: "Start the local backend from Dashboard. It serves both the HTTP API and the WebSocket bridge used for live session streaming.",
            icon: "power",
            accent: XARColors.electricEmerald,
            gradient: XARGradients.emeraldGlow
        ),
        OnboardingStep(
            title: "Assign & Monitor",
            subtitle: "Queue tickets, watch agents work",
            description: "Create tickets with project paths and acceptance criteria. Agents claim them automatically. Monitor progress in real-time with live diff streaming.",
            icon: "list.bullet.rectangle",
            accent: XARColors.electricCyan,
            gradient: XARGradients.coolGlow
        ),
        OnboardingStep(
            title: "You're Ready",
            subtitle: "Pro tips to get you started",
            description: "Use ⌘1-3 for quick navigation. ⌘⏎ approves pending agent actions. Check Mission Control for the full system overview.",
            icon: "sparkles",
            accent: XARColors.electricAmber,
            gradient: XARGradients.warmGlow
        ),
    ]

    var body: some View {
        if !defaults.hasCompletedOnboarding && !dismissed {
            ZStack {
                // Dimmed backdrop
                XARColors.void.opacity(0.85)
                    .ignoresSafeArea()

                // Animated background glow
                Circle()
                    .fill(steps[currentStep].accent.opacity(0.08))
                    .frame(width: 600, height: 600)
                    .blur(radius: 100)
                    .offset(y: -50)

                VStack(spacing: 0) {
                    Spacer()

                    // Card
                    stepCard
                        .id(currentStep)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))

                    Spacer()

                    // Navigation
                    bottomBar
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 80)

                // Skip button
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip Tour") {
                            dismiss()
                        }
                        .buttonStyle(XARButtonStyle(.ghost, size: .compact))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .animation(XARAnimation.dramatic, value: currentStep)
        }
    }

    // MARK: - Step Card

    private var stepCard: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(steps[currentStep].accent.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(steps[currentStep].gradient)
                    .floating(amplitude: 2, speed: 4)
            }

            // Text
            VStack(spacing: 10) {
                Text(steps[currentStep].title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(XARColors.textPrimary)

                Text(steps[currentStep].subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(steps[currentStep].accent)

                Text(steps[currentStep].description)
                    .font(.system(size: 14))
                    .foregroundStyle(XARColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 400)
                    .padding(.top, 4)
            }

            // Step-specific content
            if currentStep == 1 {
                serviceStatusHint
            } else if currentStep == 3 {
                shortcutGrid
            }
        }
        .padding(40)
        .frame(maxWidth: 520)
        .glowingGlass(accent: steps[currentStep].accent, glowRadius: 50)
    }

    // MARK: - Service Status Hint (Step 2)

    private var serviceStatusHint: some View {
        HStack(spacing: 16) {
            serviceIndicator("Router", running: agentService.routerStatus.state == .running)
            serviceIndicator("Bridge", running: agentService.bridgeStatus.state == .running)
        }
        .padding(.top, 8)
    }

    private func serviceIndicator(_ name: String, running: Bool) -> some View {
        HStack(spacing: 8) {
            StatusDot(running ? XARColors.statusOnline : XARColors.statusIdle, size: 8)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(XARColors.textSecondary)
            Text(running ? "Online" : "Offline")
                .font(.system(size: 11))
                .foregroundStyle(running ? XARColors.electricEmerald : XARColors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassmorphism(cornerRadius: 10)
    }

    // MARK: - Shortcut Grid (Step 4)

    private var shortcutGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(SmartDefaults.shortcuts.prefix(4).enumerated()), id: \.offset) { index, shortcut in
                HStack(spacing: 8) {
                    ShortcutHint(shortcut.key)
                    Text(shortcut.description)
                        .font(.system(size: 12))
                        .foregroundStyle(XARColors.textSecondary)
                    Spacer()
                }
                .padding(8)
                .glassmorphism(cornerRadius: 8, backgroundOpacity: 0.03)
                .staggeredAppear(index: index, delay: 0.1)
            }
        }
        .frame(maxWidth: 360)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentStep ? steps[currentStep].accent : XARColors.textTertiary)
                        .frame(width: index == currentStep ? 24 : 8, height: 8)
                        .animation(XARAnimation.snappy, value: currentStep)
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(XARButtonStyle(.ghost))
                }

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(XARButtonStyle(.primary))
                } else {
                    Button("Get Started") {
                        dismiss()
                    }
                    .buttonStyle(XARButtonStyle(.primary, size: .large))
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private func dismiss() {
        withAnimation(XARAnimation.smooth) {
            dismissed = true
        }
        defaults.completeOnboarding()
    }
}

// MARK: - Onboarding Step Model

private struct OnboardingStep {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let accent: Color
    let gradient: LinearGradient
}

// MARK: - Coach Mark

/// Highlights a specific UI element with a spotlight cutout and contextual tip.
/// Use for drawing attention to specific controls after onboarding.
struct CoachMark: View {
    let title: String
    let message: String
    let accent: Color
    let onDismiss: () -> Void

    @State private var appeared = false

    init(
        _ title: String,
        message: String,
        accent: Color = XARColors.electricCyan,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.accent = accent
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .glowPulse(color: accent)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(XARColors.textPrimary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(XARColors.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(XARColors.textSecondary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: 260)
        .glowingGlass(accent: accent, cornerRadius: 12, glowRadius: 20)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(XARAnimation.elastic.delay(0.3)) {
                appeared = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    ZStack {
        XARColors.void.ignoresSafeArea()
        OnboardingOverlay()
            .environment(AgentService())
    }
    .frame(width: 900, height: 650)
}

#Preview("Coach Mark") {
    ZStack {
        XARColors.void.ignoresSafeArea()
        CoachMark(
            "Mission Control",
            message: "This is your command center. See all agents, services, and queues at a glance.",
            accent: XARColors.electricViolet
        ) {}
    }
    .padding(40)
    .frame(width: 400, height: 200)
}
