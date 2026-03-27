import SwiftUI

// MARK: - Animation Presets

/// Curated animation curves and timing for micro-interactions.
/// Usage: `.animation(.xar.snappy)`, `withAnimation(.xar.elastic) { ... }`
public enum XARAnimation {

  // MARK: Curves

  /// Quick, responsive — buttons, toggles, small state changes
  public static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.8)

  /// Bouncy arrival — cards entering, modals appearing
  public static let elastic = Animation.spring(response: 0.5, dampingFraction: 0.65)

  /// Silky smooth — background blurs, color transitions
  public static let smooth = Animation.easeInOut(duration: 0.4)

  /// Dramatic entrance — hero elements, page transitions
  public static let dramatic = Animation.spring(response: 0.7, dampingFraction: 0.7)

  /// Gentle pulse — status indicators, breathing effects
  public static let pulse = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)

  /// Fast fade — tooltips, overlays
  public static let fade = Animation.easeOut(duration: 0.15)

  // MARK: Durations
  public static let microDuration: Double = 0.12
  public static let shortDuration: Double = 0.25
  public static let mediumDuration: Double = 0.4
}

// MARK: - Shimmer Effect

/// Animated gradient shimmer that sweeps across a view — perfect for loading states.
public struct ShimmerModifier: ViewModifier {
  @State private var phase: CGFloat = -1.0
  let speed: Double

  init(speed: Double = 1.5) {
    self.speed = speed
  }

  public func body(content: Content) -> some View {
    content
      .overlay(
        GeometryReader { geo in
          LinearGradient(
            colors: [
              .clear,
              Color.white.opacity(0.08),
              Color.white.opacity(0.15),
              Color.white.opacity(0.08),
              .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: geo.size.width * 0.6)
          .offset(x: phase * (geo.size.width * 1.6) - geo.size.width * 0.3)
          .onAppear {
            withAnimation(
              .linear(duration: speed).repeatForever(autoreverses: false)
            ) {
              phase = 1.0
            }
          }
        }
      )
      .clipped()
  }
}

// MARK: - Glow Pulse Effect

/// Pulsing glow ring around a view — great for active/live status indicators.
public struct GlowPulseModifier: ViewModifier {
  let color: Color
  let intensity: CGFloat
  @State private var isGlowing = false

  public func body(content: Content) -> some View {
    content
      .shadow(color: color.opacity(isGlowing ? intensity : intensity * 0.3), radius: isGlowing ? 12 : 4)
      .onAppear {
        withAnimation(XARAnimation.pulse) {
          isGlowing = true
        }
      }
  }
}

// MARK: - Stagger Animation

/// Delays appearance of child views for a cascading entrance effect.
public struct StaggeredAppearModifier: ViewModifier {
  let index: Int
  let baseDelay: Double
  @State private var appeared = false

  public func body(content: Content) -> some View {
    content
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared ? 0 : 16)
      .onAppear {
        withAnimation(XARAnimation.elastic.delay(Double(index) * baseDelay)) {
          appeared = true
        }
      }
  }
}

// MARK: - Float Animation

/// Gentle floating motion — makes elements feel alive and weightless.
public struct FloatModifier: ViewModifier {
  let amplitude: CGFloat
  let speed: Double
  @State private var floating = false

  public func body(content: Content) -> some View {
    content
      .offset(y: floating ? -amplitude : amplitude)
      .onAppear {
        withAnimation(
          .easeInOut(duration: speed).repeatForever(autoreverses: true)
        ) {
          floating = true
        }
      }
  }
}

// MARK: - View Extensions

public extension View {
  /// Add a sweeping shimmer effect (great for loading skeletons)
  func shimmer(speed: Double = 1.5) -> some View {
    modifier(ShimmerModifier(speed: speed))
  }

  /// Add a pulsing glow ring
  func glowPulse(color: Color = XARColors.electricCyan, intensity: CGFloat = 0.6) -> some View {
    modifier(GlowPulseModifier(color: color, intensity: intensity))
  }

  /// Stagger entrance animation based on index
  func staggeredAppear(index: Int, delay: Double = 0.08) -> some View {
    modifier(StaggeredAppearModifier(index: index, baseDelay: delay))
  }

  /// Gentle floating motion
  func floating(amplitude: CGFloat = 3, speed: Double = 3.0) -> some View {
    modifier(FloatModifier(amplitude: amplitude, speed: speed))
  }
}
