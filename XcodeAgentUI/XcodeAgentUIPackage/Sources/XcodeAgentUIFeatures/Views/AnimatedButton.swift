import SwiftUI
import XcodeAgentUICore

// MARK: - Animated Button Style

/// Bold, glassmorphic button with press/hover micro-interactions and optional gradient fill.
///
/// ```swift
/// Button("Launch Agent") { ... }
///   .buttonStyle(XARButtonStyle(.primary))
///
/// Button("Cancel") { ... }
///   .buttonStyle(XARButtonStyle(.ghost))
/// ```
struct XARButtonStyle: ButtonStyle {
  let variant: Variant
  let size: Size

  enum Variant {
    case primary    // Gradient fill, white text — main CTAs
    case secondary  // Glass fill, accent text — secondary actions
    case ghost      // Transparent, subtle hover — tertiary actions
    case danger     // Red gradient — destructive actions
  }

  enum Size {
    case compact
    case regular
    case large

    var horizontalPadding: CGFloat {
      switch self {
      case .compact: return 12
      case .regular: return 20
      case .large: return 28
      }
    }

    var verticalPadding: CGFloat {
      switch self {
      case .compact: return 6
      case .regular: return 10
      case .large: return 14
      }
    }

    var fontSize: CGFloat {
      switch self {
      case .compact: return 12
      case .regular: return 13
      case .large: return 15
      }
    }
  }

  init(_ variant: Variant = .primary, size: Size = .regular) {
    self.variant = variant
    self.size = size
  }

  func makeBody(configuration: Configuration) -> some View {
    ButtonBody(variant: variant, size: size, configuration: configuration)
  }

  // Separate struct to hold @State
  private struct ButtonBody: View {
    let variant: Variant
    let size: Size
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
      configuration.label
        .font(.system(size: size.fontSize, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: size == .large ? 12 : 9))
        .overlay(border)
        .shadow(color: shadowColor, radius: configuration.isPressed ? 4 : (isHovered ? 12 : 6), y: 2)
        .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
        .brightness(configuration.isPressed ? -0.05 : 0)
        .animation(XARAnimation.snappy, value: configuration.isPressed)
        .animation(XARAnimation.snappy, value: isHovered)
        .onHover { hovering in
          isHovered = hovering
        }
    }

    @ViewBuilder
    private var background: some View {
      switch variant {
      case .primary:
        XARGradients.heroGlow

      case .secondary:
        ZStack {
          RoundedRectangle(cornerRadius: 9)
            .fill(.ultraThinMaterial)
          RoundedRectangle(cornerRadius: 9)
            .fill(XARColors.electricViolet.opacity(isHovered ? 0.15 : 0.08))
        }

      case .ghost:
        Color.white.opacity(isHovered ? 0.06 : 0.0)

      case .danger:
        LinearGradient(
          colors: [XARColors.statusError, XARColors.electricPink],
          startPoint: .leading,
          endPoint: .trailing
        )
      }
    }

    @ViewBuilder
    private var border: some View {
      switch variant {
      case .primary, .danger:
        RoundedRectangle(cornerRadius: 9)
          .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)

      case .secondary:
        RoundedRectangle(cornerRadius: 9)
          .strokeBorder(XARColors.electricViolet.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)

      case .ghost:
        RoundedRectangle(cornerRadius: 9)
          .strokeBorder(Color.white.opacity(isHovered ? 0.1 : 0), lineWidth: 1)
      }
    }

    private var foregroundColor: Color {
      switch variant {
      case .primary, .danger: return .white
      case .secondary: return XARColors.electricViolet
      case .ghost: return XARColors.textSecondary
      }
    }

    private var shadowColor: Color {
      switch variant {
      case .primary: return XARColors.electricViolet.opacity(0.3)
      case .secondary: return XARColors.electricViolet.opacity(0.15)
      case .ghost: return .clear
      case .danger: return XARColors.statusError.opacity(0.3)
      }
    }
  }
}

// MARK: - Icon Button

/// Circular icon button with glass background and hover glow.
struct XARIconButton: View {
  let icon: String
  let accent: Color
  let size: CGFloat
  let action: () -> Void

  @State private var isHovered = false
  @State private var isPressed = false

  init(
    _ icon: String,
    accent: Color = XARColors.electricCyan,
    size: CGFloat = 32,
    action: @escaping () -> Void
  ) {
    self.icon = icon
    self.accent = accent
    self.size = size
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: size * 0.4, weight: .medium))
        .foregroundStyle(isHovered ? accent : XARColors.textSecondary)
        .frame(width: size, height: size)
        .background {
          Circle()
            .fill(.ultraThinMaterial)
            .opacity(0.7)
          Circle()
            .fill(accent.opacity(isHovered ? 0.12 : 0))
        }
        .clipShape(Circle())
        .overlay(
          Circle()
            .strokeBorder(
              accent.opacity(isHovered ? 0.35 : 0.1),
              lineWidth: 1
            )
        )
        .shadow(color: accent.opacity(isHovered ? 0.3 : 0), radius: 8)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(XARAnimation.snappy, value: isHovered)
        .animation(XARAnimation.snappy, value: isPressed)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Pill Tag

/// Small pill-shaped tag with gradient background — perfect for labels and badges.
struct PillTag: View {
  let text: String
  let color: Color

  init(_ text: String, color: Color = XARColors.electricCyan) {
    self.text = text
    self.color = color
  }

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .bold))
      .textCase(.uppercase)
      .tracking(0.5)
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        Capsule()
          .fill(
            LinearGradient(
              colors: [color, color.opacity(0.7)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
      )
      .shadow(color: color.opacity(0.3), radius: 4)
  }
}

// MARK: - Preview

#Preview("Button Variants") {
  VStack(spacing: 16) {
    Button("Launch Agent") {}
      .buttonStyle(XARButtonStyle(.primary))

    Button("Configure") {}
      .buttonStyle(XARButtonStyle(.secondary))

    Button("Cancel") {}
      .buttonStyle(XARButtonStyle(.ghost))

    Button("Delete Session") {}
      .buttonStyle(XARButtonStyle(.danger))

    HStack(spacing: 12) {
      XARIconButton("play.fill", accent: XARColors.electricEmerald) {}
      XARIconButton("stop.fill", accent: XARColors.statusError) {}
      XARIconButton("arrow.clockwise", accent: XARColors.electricBlue) {}
    }

    HStack(spacing: 8) {
      PillTag("Running", color: XARColors.electricEmerald)
      PillTag("Opus", color: XARColors.electricViolet)
      PillTag("Priority", color: XARColors.electricAmber)
    }
  }
  .padding(40)
  .frame(width: 400, height: 400)
  .background(XARColors.void)
}

#Preview("Styled Cards") {
  VStack(spacing: 16) {
    StyledCard("Active Agents", icon: "bolt.fill", accent: XARColors.electricCyan) {
      HStack(spacing: 12) {
        StatCard("Running", value: "3", trend: .up("+2"), accent: XARColors.electricEmerald)
        StatCard("Queued", value: "7", accent: XARColors.electricAmber)
        StatCard("Failed", value: "0", trend: .neutral("Stable"), accent: XARColors.statusError)
      }
    }

    StyledCard("System Status", icon: "waveform", accent: XARColors.electricViolet, showGlow: true) {
      HStack {
        StatusDot(XARColors.statusOnline)
        Text("All systems nominal")
          .font(.system(size: 13))
          .foregroundStyle(XARColors.textSecondary)
      }
    }
  }
  .padding(24)
  .frame(width: 700, height: 400)
  .background(XARColors.void)
}
