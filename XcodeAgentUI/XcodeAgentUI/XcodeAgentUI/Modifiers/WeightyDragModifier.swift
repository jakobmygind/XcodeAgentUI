import SwiftUI

// MARK: - Weighty Drag Modifier

/// Adds physics-based drag with momentum, friction, and rubber-banding at edges.
/// Dragged items feel heavy and real — they overshoot slightly and settle.
struct WeightyDragModifier: ViewModifier {
  @State private var offset: CGSize = .zero
  @State private var isDragging = false

  let axis: Axis
  let resistance: CGFloat       // How much the view resists being dragged (0.0 = free, 1.0 = stuck)
  let rubberBandLimit: CGFloat  // How far it stretches past bounds before snapping
  let onDragEnd: ((CGSize) -> Void)?

  init(
    axis: Axis = .vertical,
    resistance: CGFloat = 0.3,
    rubberBandLimit: CGFloat = 80,
    onDragEnd: ((CGSize) -> Void)? = nil
  ) {
    self.axis = axis
    self.resistance = resistance
    self.rubberBandLimit = rubberBandLimit
    self.onDragEnd = onDragEnd
  }

  func body(content: Content) -> some View {
    content
      .offset(appliedOffset)
      .scaleEffect(isDragging ? 1.02 : 1.0)
      .shadow(
        color: isDragging ? XARColors.electricCyan.opacity(0.2) : .clear,
        radius: isDragging ? 20 : 0,
        y: isDragging ? 8 : 0
      )
      .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDragging)
      .gesture(dragGesture)
  }

  private var appliedOffset: CGSize {
    switch axis {
    case .horizontal:
      return CGSize(width: rubberBand(offset.width), height: 0)
    case .vertical:
      return CGSize(width: 0, height: rubberBand(offset.height))
    }
  }

  /// Rubber-band function: the further you drag, the harder it resists.
  /// Creates the iOS-style elastic overscroll feel.
  private func rubberBand(_ value: CGFloat) -> CGFloat {
    let clamped = min(abs(value), rubberBandLimit * 3)
    let dampened = rubberBandLimit * (1 - exp(-clamped / rubberBandLimit))
    return value < 0 ? -dampened : dampened
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { gesture in
        isDragging = true
        let translation = gesture.translation
        let dampedTranslation = CGSize(
          width: translation.width * (1 - resistance),
          height: translation.height * (1 - resistance)
        )
        offset = dampedTranslation
      }
      .onEnded { gesture in
        isDragging = false
        onDragEnd?(offset)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
          offset = .zero
        }
      }
  }
}

// MARK: - Drag-to-Reorder Item Modifier

/// Applies to list items: lifts them up with shadow on drag, snaps to position on release.
struct DragReorderModifier: ViewModifier {
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  let onReorder: (CGFloat) -> Void

  func body(content: Content) -> some View {
    content
      .offset(y: dragOffset)
      .zIndex(isDragging ? 100 : 0)
      .scaleEffect(isDragging ? 1.04 : 1.0)
      .shadow(
        color: isDragging ? XARColors.electricViolet.opacity(0.3) : .clear,
        radius: isDragging ? 16 : 0,
        y: isDragging ? 6 : 0
      )
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
      .gesture(
        DragGesture()
          .onChanged { value in
            isDragging = true
            dragOffset = value.translation.height
          }
          .onEnded { value in
            isDragging = false
            onReorder(value.translation.height)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
              dragOffset = 0
            }
          }
      )
  }
}

// MARK: - Inertial Scroll Velocity Tracker

/// Tracks scroll velocity for momentum-based effects (parallax headers, pull-to-refresh).
struct ScrollVelocityModifier: ViewModifier {
  @State private var scrollOffset: CGFloat = 0
  @State private var velocity: CGFloat = 0
  let onVelocityChange: (CGFloat) -> Void

  func body(content: Content) -> some View {
    content
      .background(
        GeometryReader { geo in
          Color.clear.preference(
            key: ScrollOffsetKey.self,
            value: geo.frame(in: .global).minY
          )
        }
      )
      .onPreferenceChange(ScrollOffsetKey.self) { newOffset in
        velocity = newOffset - scrollOffset
        scrollOffset = newOffset
        onVelocityChange(velocity)
      }
  }
}

private struct ScrollOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - View Extensions

extension View {
  /// Weighty drag with physics
  func weightyDrag(
    axis: Axis = .vertical,
    resistance: CGFloat = 0.3,
    rubberBandLimit: CGFloat = 80,
    onDragEnd: ((CGSize) -> Void)? = nil
  ) -> some View {
    modifier(
      WeightyDragModifier(
        axis: axis,
        resistance: resistance,
        rubberBandLimit: rubberBandLimit,
        onDragEnd: onDragEnd
      )
    )
  }

  /// Drag-to-reorder with lift effect
  func dragReorder(onReorder: @escaping (CGFloat) -> Void) -> some View {
    modifier(DragReorderModifier(onReorder: onReorder))
  }

  /// Track scroll velocity for momentum effects
  func scrollVelocity(onChange: @escaping (CGFloat) -> Void) -> some View {
    modifier(ScrollVelocityModifier(onVelocityChange: onChange))
  }
}
