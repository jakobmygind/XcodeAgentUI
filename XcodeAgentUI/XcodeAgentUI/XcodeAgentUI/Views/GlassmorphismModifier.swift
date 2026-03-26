import SwiftUI

// MARK: - Glassmorphism Card Modifier

/// Frosted-glass effect with luminous border and depth shadows.
/// The cornerstone of the visual upgrade — apply to any container.
///
/// ```swift
/// VStack { ... }
///   .glassmorphism()                          // default
///   .glassmorphism(cornerRadius: 20, border: .electricPink)  // custom
/// ```
struct GlassmorphismModifier: ViewModifier {
  let cornerRadius: CGFloat
  let borderColor: Color
  let borderWidth: CGFloat
  let backgroundOpacity: Double
  let blurRadius: CGFloat

  init(
    cornerRadius: CGFloat = 16,
    borderColor: Color = XARColors.glassBorder,
    borderWidth: CGFloat = 1,
    backgroundOpacity: Double = 0.06,
    blurRadius: CGFloat = 20
  ) {
    self.cornerRadius = cornerRadius
    self.borderColor = borderColor
    self.borderWidth = borderWidth
    self.backgroundOpacity = backgroundOpacity
    self.blurRadius = blurRadius
  }

  func body(content: Content) -> some View {
    content
      .background {
        ZStack {
          // Deep frosted base
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .opacity(0.7)

          // Tinted overlay
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(backgroundOpacity))

          // Top-edge highlight (simulates overhead light)
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(0.12),
                  Color.white.opacity(0.02),
                  .clear,
                ],
                startPoint: .top,
                endPoint: .center
              )
            )
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            LinearGradient(
              colors: [
                borderColor.opacity(0.5),
                borderColor.opacity(0.15),
                borderColor.opacity(0.05),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: borderWidth
          )
      )
      // Depth shadow stack: soft ambient + sharp contact
      .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
      .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
  }
}

// MARK: - Accent-Glow Glass Variant

/// Glass card with a colored glow bleeding from behind — for hero/featured cards.
struct GlowingGlassModifier: ViewModifier {
  let accentColor: Color
  let cornerRadius: CGFloat
  let glowRadius: CGFloat

  init(accent: Color = XARColors.electricViolet, cornerRadius: CGFloat = 16, glowRadius: CGFloat = 40) {
    self.accentColor = accent
    self.cornerRadius = cornerRadius
    self.glowRadius = glowRadius
  }

  func body(content: Content) -> some View {
    content
      .background {
        // Glow layer sits behind the glass
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(accentColor.opacity(0.15))
          .blur(radius: glowRadius)
          .offset(y: 4)
      }
      .modifier(
        GlassmorphismModifier(
          cornerRadius: cornerRadius,
          borderColor: accentColor.opacity(0.3)
        )
      )
  }
}

// MARK: - Inner-Glow Border

/// Adds a soft inner glow along the edges — great for selected/active states.
struct InnerGlowModifier: ViewModifier {
  let color: Color
  let cornerRadius: CGFloat
  let lineWidth: CGFloat

  func body(content: Content) -> some View {
    content
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(color.opacity(0.4), lineWidth: lineWidth)
          .blur(radius: 3)
          .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(color.opacity(0.2), lineWidth: lineWidth * 0.5)
      )
  }
}

// MARK: - View Extensions

extension View {
  /// Apply the standard glassmorphism treatment
  func glassmorphism(
    cornerRadius: CGFloat = 16,
    borderColor: Color = XARColors.glassBorder,
    backgroundOpacity: Double = 0.06
  ) -> some View {
    modifier(
      GlassmorphismModifier(
        cornerRadius: cornerRadius,
        borderColor: borderColor,
        backgroundOpacity: backgroundOpacity
      )
    )
  }

  /// Glass card with a colored glow behind it
  func glowingGlass(
    accent: Color = XARColors.electricViolet,
    cornerRadius: CGFloat = 16,
    glowRadius: CGFloat = 40
  ) -> some View {
    modifier(GlowingGlassModifier(accent: accent, cornerRadius: cornerRadius, glowRadius: glowRadius))
  }

  /// Soft inner-glow border for selected states
  func innerGlow(
    color: Color = XARColors.electricCyan,
    cornerRadius: CGFloat = 16,
    lineWidth: CGFloat = 2
  ) -> some View {
    modifier(InnerGlowModifier(color: color, cornerRadius: cornerRadius, lineWidth: lineWidth))
  }
}
