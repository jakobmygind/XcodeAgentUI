import SwiftUI

// MARK: - Elastic Press Button Style

/// Button style with spring-physics press feedback.
/// On press: squishes down with elastic bounce. On release: springs back with overshoot.
/// Feels like pressing a physical rubber button.
struct ElasticButtonStyle: ButtonStyle {
  let intensity: Intensity

  enum Intensity {
    case light   // Subtle — for icon buttons, small controls
    case medium  // Default — for standard action buttons
    case heavy   // Dramatic — for primary CTAs, hero actions

    var pressScale: CGFloat {
      switch self {
      case .light: return 0.97
      case .medium: return 0.93
      case .heavy: return 0.88
      }
    }

    var response: Double {
      switch self {
      case .light: return 0.25
      case .medium: return 0.3
      case .heavy: return 0.4
      }
    }

    var damping: Double {
      switch self {
      case .light: return 0.7
      case .medium: return 0.6
      case .heavy: return 0.55
      }
    }
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(
        configuration.isPressed ? intensity.pressScale : 1.0,
        anchor: .center
      )
      .brightness(configuration.isPressed ? -0.03 : 0)
      .animation(
        .spring(response: intensity.response, dampingFraction: intensity.damping),
        value: configuration.isPressed
      )
  }
}

// MARK: - Jelly Hover Modifier

/// Adds a squishy, jelly-like hover effect.
/// The view subtly inflates on hover and deflates when the cursor leaves.
struct JellyHoverModifier: ViewModifier {
  @State private var isHovered = false
  let inflateScale: CGFloat
  let glowColor: Color

  init(inflateScale: CGFloat = 1.03, glowColor: Color = XARColors.electricCyan) {
    self.inflateScale = inflateScale
    self.glowColor = glowColor
  }

  func body(content: Content) -> some View {
    content
      .scaleEffect(isHovered ? inflateScale : 1.0)
      .shadow(
        color: isHovered ? glowColor.opacity(0.3) : .clear,
        radius: isHovered ? 12 : 0
      )
      .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHovered)
      .onHover { hovering in
        isHovered = hovering
      }
  }
}

// MARK: - Magnetic Snap Modifier

/// Creates a magnetic "snap" effect — the view resists movement near edges
/// and snaps into place with a satisfying spring when released.
struct MagneticSnapModifier: ViewModifier {
  @State private var snapPhase: CGFloat = 0

  func body(content: Content) -> some View {
    content
      .offset(y: snapPhase)
      .onAppear {
        // Simulate a snap-into-place on appearance
        snapPhase = 8
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
          snapPhase = 0
        }
      }
  }
}

// MARK: - Ripple Press Modifier

/// Radiating ripple effect on tap — visual feedback that spreads from the touch point.
struct RipplePressModifier: ViewModifier {
  let color: Color
  @State private var rippleActive = false
  @State private var rippleOpacity: Double = 0.4

  init(color: Color = XARColors.electricCyan) {
    self.color = color
  }

  func body(content: Content) -> some View {
    content
      .overlay(
        Circle()
          .fill(color.opacity(rippleOpacity))
          .scaleEffect(rippleActive ? 2.5 : 0.1)
          .opacity(rippleActive ? 0 : rippleOpacity)
          .animation(.easeOut(duration: 0.5), value: rippleActive)
      )
      .clipped()
      .onTapGesture {
        rippleActive = false
        rippleOpacity = 0.4
        withAnimation {
          rippleActive = true
        }
        Task { try? await Task.sleep(for: .milliseconds(600)); rippleActive = false }
      }
  }
}

// MARK: - View Extensions

extension View {
  /// Elastic button press with configurable intensity
  func elasticPress(_ intensity: ElasticButtonStyle.Intensity = .medium) -> some View {
    buttonStyle(ElasticButtonStyle(intensity: intensity))
  }

  /// Jelly-like hover inflation
  func jellyHover(scale: CGFloat = 1.03, glow: Color = XARColors.electricCyan) -> some View {
    modifier(JellyHoverModifier(inflateScale: scale, glowColor: glow))
  }

  /// Magnetic snap-into-place on appearance
  func magneticSnap() -> some View {
    modifier(MagneticSnapModifier())
  }

  /// Ripple press feedback
  func ripplePress(color: Color = XARColors.electricCyan) -> some View {
    modifier(RipplePressModifier(color: color))
  }
}
