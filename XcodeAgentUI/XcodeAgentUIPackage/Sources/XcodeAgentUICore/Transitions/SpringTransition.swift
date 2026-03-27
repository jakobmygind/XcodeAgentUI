import SwiftUI

// MARK: - Spring-Physics View Transitions

/// Custom AnyTransition presets powered by spring dynamics.
/// These create the feeling of views having real physical mass and momentum.
extension AnyTransition {

  /// Slide in from the trailing edge with spring overshoot — the default view-switch transition.
  static var springSlide: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: SpringSlideModifier(offset: 60, opacity: 0, scale: 0.94),
        identity: SpringSlideModifier(offset: 0, opacity: 1, scale: 1)
      ),
      removal: .modifier(
        active: SpringSlideModifier(offset: -40, opacity: 0, scale: 0.96),
        identity: SpringSlideModifier(offset: 0, opacity: 1, scale: 1)
      )
    )
  }

  /// Scale up from center with elastic bounce — for modals, cards, popovers.
  static var springScale: AnyTransition {
    .modifier(
      active: SpringScaleModifier(scale: 0.7, opacity: 0, blur: 8),
      identity: SpringScaleModifier(scale: 1, opacity: 1, blur: 0)
    )
  }

  /// Rise from below with parallax depth — for panels and sheets.
  static var springRise: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: SpringRiseModifier(offsetY: 80, opacity: 0, scale: 0.92),
        identity: SpringRiseModifier(offsetY: 0, opacity: 1, scale: 1)
      ),
      removal: .modifier(
        active: SpringRiseModifier(offsetY: 50, opacity: 0, scale: 0.95),
        identity: SpringRiseModifier(offsetY: 0, opacity: 1, scale: 1)
      )
    )
  }

  /// Morph-fade for content swaps — subtle scale + opacity.
  static var morphFade: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: MorphFadeModifier(opacity: 0, scale: 1.04, blur: 4),
        identity: MorphFadeModifier(opacity: 1, scale: 1, blur: 0)
      ),
      removal: .modifier(
        active: MorphFadeModifier(opacity: 0, scale: 0.96, blur: 4),
        identity: MorphFadeModifier(opacity: 1, scale: 1, blur: 0)
      )
    )
  }
}

// MARK: - Transition Geometry Modifiers

private struct SpringSlideModifier: ViewModifier {
  let offset: CGFloat
  let opacity: Double
  let scale: CGFloat

  func body(content: Content) -> some View {
    content
      .offset(x: offset)
      .opacity(opacity)
      .scaleEffect(scale)
  }
}

private struct SpringScaleModifier: ViewModifier {
  let scale: CGFloat
  let opacity: Double
  let blur: CGFloat

  func body(content: Content) -> some View {
    content
      .scaleEffect(scale)
      .opacity(opacity)
      .blur(radius: blur)
  }
}

private struct SpringRiseModifier: ViewModifier {
  let offsetY: CGFloat
  let opacity: Double
  let scale: CGFloat

  func body(content: Content) -> some View {
    content
      .offset(y: offsetY)
      .opacity(opacity)
      .scaleEffect(scale, anchor: .bottom)
  }
}

private struct MorphFadeModifier: ViewModifier {
  let opacity: Double
  let scale: CGFloat
  let blur: CGFloat

  func body(content: Content) -> some View {
    content
      .opacity(opacity)
      .scaleEffect(scale)
      .blur(radius: blur)
  }
}

// MARK: - Animated Navigation Container

/// Wraps content switching with spring-physics transitions.
/// Use this instead of raw `switch` for sidebar → detail navigation.
///
/// ```swift
/// SpringNavigationContainer(selection: $currentView) {
///   MissionControlView()
/// }
/// ```
struct SpringNavigationContainer<Content: View>: View {
  let selection: AnyHashable
  @ViewBuilder let content: () -> Content

  @State private var animationDirection: Edge = .trailing

  var body: some View {
    content()
      .id(selection)
      .transition(.springSlide)
      .animation(.spring(response: 0.45, dampingFraction: 0.82), value: selection)
  }
}

// MARK: - View Transition Coordinator

/// Applies coordinated spring transitions to a view based on appearance phase.
public struct ViewTransitionModifier: ViewModifier {
  public let style: TransitionStyle
  @State private var appeared = false

  public enum TransitionStyle {
    case slide      // Horizontal entrance
    case rise       // Vertical entrance
    case scale      // Center-out entrance
    case morph      // Subtle content swap
  }

  public init(style: TransitionStyle) {
    self.style = style
  }

  public func body(content: Content) -> some View {
    content
      .modifier(transitionGeometry)
      .onAppear {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
          appeared = true
        }
      }
  }

  private var transitionGeometry: some ViewModifier {
    TransitionGeometryModifier(
      style: style,
      appeared: appeared
    )
  }
}

private struct TransitionGeometryModifier: ViewModifier {
  let style: ViewTransitionModifier.TransitionStyle
  let appeared: Bool

  func body(content: Content) -> some View {
    switch style {
    case .slide:
      content
        .offset(x: appeared ? 0 : 50)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
    case .rise:
      content
        .offset(y: appeared ? 0 : 60)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.93, anchor: .bottom)
    case .scale:
      content
        .scaleEffect(appeared ? 1 : 0.75)
        .opacity(appeared ? 1 : 0)
        .blur(radius: appeared ? 0 : 6)
    case .morph:
      content
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 1.03)
        .blur(radius: appeared ? 0 : 3)
    }
  }
}

// MARK: - View Extensions

public extension View {
  /// Apply a spring-physics entrance transition
  public func springEntrance(_ style: ViewTransitionModifier.TransitionStyle = .slide) -> some View {
    modifier(ViewTransitionModifier(style: style))
  }
}
