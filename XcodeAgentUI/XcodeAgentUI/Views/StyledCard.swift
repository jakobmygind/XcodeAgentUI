import SwiftUI

// MARK: - Styled Card

/// A premium glassmorphism card with optional accent glow, header, and icon.
/// Drop-in replacement for `GroupBox` that looks portfolio-worthy.
///
/// ```swift
/// StyledCard("Active Sessions", icon: "bolt.fill", accent: .electricCyan) {
///   Text("3 agents running")
/// }
/// ```
struct StyledCard<Content: View>: View {
  let title: String?
  let icon: String?
  let accent: Color
  let showGlow: Bool
  @ViewBuilder let content: () -> Content

  @State private var isHovered = false

  init(
    _ title: String? = nil,
    icon: String? = nil,
    accent: Color = XARColors.electricViolet,
    showGlow: Bool = false,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.icon = icon
    self.accent = accent
    self.showGlow = showGlow
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title {
        HStack(spacing: 8) {
          if let icon {
            Image(systemName: icon)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(accent)
              .frame(width: 28, height: 28)
              .background(accent.opacity(0.15))
              .clipShape(RoundedRectangle(cornerRadius: 7))
          }

          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(XARColors.textPrimary)

          Spacer()
        }

        // Gradient divider
        Rectangle()
          .fill(
            LinearGradient(
              colors: [accent.opacity(0.5), accent.opacity(0.05)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(height: 1)
      }

      content()
    }
    .padding(16)
    .if(showGlow) { view in
      view.glowingGlass(accent: accent)
    }
    .if(!showGlow) { view in
      view.glassmorphism(borderColor: isHovered ? accent.opacity(0.3) : XARColors.glassBorder)
    }
    .scaleEffect(isHovered ? 1.008 : 1.0)
    .animation(XARAnimation.snappy, value: isHovered)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Stat Card

/// Compact card for displaying a single metric with a label, value, and trend.
struct StatCard: View {
  let label: String
  let value: String
  let trend: Trend?
  let accent: Color

  @State private var appeared = false

  enum Trend {
    case up(String)
    case down(String)
    case neutral(String)

    var color: Color {
      switch self {
      case .up: return XARColors.electricEmerald
      case .down: return XARColors.statusError
      case .neutral: return XARColors.textSecondary
      }
    }

    var icon: String {
      switch self {
      case .up: return "arrow.up.right"
      case .down: return "arrow.down.right"
      case .neutral: return "arrow.right"
      }
    }

    var text: String {
      switch self {
      case .up(let s), .down(let s), .neutral(let s): return s
      }
    }
  }

  init(_ label: String, value: String, trend: Trend? = nil, accent: Color = XARColors.electricBlue) {
    self.label = label
    self.value = value
    self.trend = trend
    self.accent = accent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(XARColors.textSecondary)
        .textCase(.uppercase)
        .tracking(0.5)

      Text(value)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(XARColors.textPrimary)
        .contentTransition(.numericText())

      if let trend {
        HStack(spacing: 4) {
          Image(systemName: trend.icon)
            .font(.system(size: 10, weight: .bold))
          Text(trend.text)
            .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(trend.color)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background {
      // Accent gradient underlay
      LinearGradient(
        colors: [accent.opacity(0.08), .clear],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
      )
    }
    .glassmorphism(borderColor: accent.opacity(0.15))
    .opacity(appeared ? 1 : 0)
    .offset(y: appeared ? 0 : 12)
    .onAppear {
      withAnimation(XARAnimation.elastic) {
        appeared = true
      }
    }
  }
}

// MARK: - Status Dot

/// Animated status indicator with glow pulse.
struct StatusDot: View {
  let color: Color
  let size: CGFloat
  let animated: Bool

  init(_ color: Color = XARColors.statusOnline, size: CGFloat = 8, animated: Bool = true) {
    self.color = color
    self.size = size
    self.animated = animated
  }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .if(animated) { view in
        view.glowPulse(color: color, intensity: 0.8)
      }
  }
}

// MARK: - Conditional Modifier Helper

extension View {
  @ViewBuilder
  func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
