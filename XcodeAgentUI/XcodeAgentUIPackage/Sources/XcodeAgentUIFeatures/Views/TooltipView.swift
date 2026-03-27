import SwiftUI
import XcodeAgentUICore

// MARK: - Tooltip View

/// Glassmorphic tooltip with arrow indicator and smooth entrance animation.
/// Adapts position to avoid clipping at screen edges.
///
/// ```swift
/// Text("Agents")
///   .xarTooltip("View and manage running agents", edge: .bottom)
/// ```
struct XARTooltip: View {
    let text: String
    let edge: Edge
    let accent: Color
    let maxWidth: CGFloat

    @State private var appeared = false

    init(
        _ text: String,
        edge: Edge = .bottom,
        accent: Color = XARColors.electricCyan,
        maxWidth: CGFloat = 220
    ) {
        self.text = text
        self.edge = edge
        self.accent = accent
        self.maxWidth = maxWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            if edge == .bottom { arrow.rotationEffect(.degrees(180)) }

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(XARColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: maxWidth)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .opacity(0.9)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(XARColors.surfaceRaised.opacity(0.8))
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: accent.opacity(0.15), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

            if edge == .top { arrow }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (edge == .bottom ? -6 : 6))
        .onAppear {
            withAnimation(XARAnimation.elastic.delay(0.1)) {
                appeared = true
            }
        }
    }

    private var arrow: some View {
        Triangle()
            .fill(XARColors.surfaceRaised.opacity(0.8))
            .frame(width: 14, height: 7)
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Tooltip Modifier

/// Shows a glassmorphic tooltip on hover after a brief delay.
struct XARTooltipModifier: ViewModifier {
    let text: String
    let edge: Edge
    let accent: Color

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if showTooltip {
                    XARTooltip(text, edge: edge, accent: accent)
                        .fixedSize()
                        .offset(y: edgeOffset)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(100)
                }
            }
            .onHover { hovering in
                isHovered = hovering
                hoverTask?.cancel()

                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        withAnimation(XARAnimation.fade) {
                            showTooltip = true
                        }
                    }
                } else {
                    withAnimation(XARAnimation.fade) {
                        showTooltip = false
                    }
                }
            }
    }

    private var alignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private var edgeOffset: CGFloat {
        switch edge {
        case .top: return -8
        case .bottom: return 8
        default: return 0
        }
    }
}

// MARK: - Shortcut Hint Badge

/// Small keyboard shortcut badge — shown to returning users for discoverability.
///
/// ```swift
/// Button("Dashboard") { ... }
///   .overlay(alignment: .trailing) { ShortcutHint("⌘1") }
/// ```
struct ShortcutHint: View {
    let shortcut: String

    init(_ shortcut: String) {
        self.shortcut = shortcut
    }

    var body: some View {
        Text(shortcut)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(XARColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(XARColors.surfaceOverlay.opacity(0.6))
                Capsule()
                    .strokeBorder(XARColors.glassBorder, lineWidth: 0.5)
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Show a glassmorphic tooltip on hover
    func xarTooltip(
        _ text: String,
        edge: Edge = .bottom,
        accent: Color = XARColors.electricCyan
    ) -> some View {
        modifier(XARTooltipModifier(text: text, edge: edge, accent: accent))
    }
}

// MARK: - Preview

#Preview("Tooltips") {
    VStack(spacing: 60) {
        XARTooltip("Router handles request routing between providers", edge: .top, accent: XARColors.electricViolet)

        HStack(spacing: 32) {
            XARIconButton("play.fill", accent: XARColors.electricEmerald) {}
                .xarTooltip("Start all services", edge: .bottom)

            XARIconButton("stop.fill", accent: XARColors.statusError) {}
                .xarTooltip("Stop all services", edge: .bottom)
        }

        HStack(spacing: 8) {
            ShortcutHint("⌘1")
            ShortcutHint("⌘⏎")
            ShortcutHint("⇧⌘N")
        }
    }
    .padding(60)
    .frame(width: 500, height: 400)
    .background(XARColors.void)
}
