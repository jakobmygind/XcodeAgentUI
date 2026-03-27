import SwiftUI

// MARK: - Color Palette

/// Bold, dark-mode-first color system with electric accents and deep backgrounds.
/// Usage: `Color.xar.electricViolet`, `LinearGradient.xar.heroGlow`
public enum XARColors {

  // MARK: Core Backgrounds
  public static let void = Color(hex: 0x0A0A0F)
  public static let surface = Color(hex: 0x12121A)
  public static let surfaceRaised = Color(hex: 0x1A1A26)
  public static let surfaceOverlay = Color(hex: 0x22222F)

  // MARK: Electric Accents
  public static let electricViolet = Color(hex: 0x8B5CF6)
  public static let electricBlue = Color(hex: 0x3B82F6)
  public static let electricCyan = Color(hex: 0x06B6D4)
  public static let electricPink = Color(hex: 0xEC4899)
  public static let electricAmber = Color(hex: 0xF59E0B)
  public static let electricEmerald = Color(hex: 0x10B981)

  // MARK: Status Colors
  public static let statusOnline = Color(hex: 0x22D3EE)
  public static let statusWarning = Color(hex: 0xFBBF24)
  public static let statusError = Color(hex: 0xF43F5E)
  public static let statusIdle = Color(hex: 0x6B7280)

  // MARK: Text
  public static let textPrimary = Color.white
  public static let textSecondary = Color.white.opacity(0.6)
  public static let textTertiary = Color.white.opacity(0.35)

  // MARK: Glass
  public static let glassBorder = Color.white.opacity(0.08)
  public static let glassHighlight = Color.white.opacity(0.05)
  public static let glassFill = Color.white.opacity(0.03)
}

// MARK: - Gradient Presets

public enum XARGradients {

  public static let heroGlow = LinearGradient(
    colors: [XARColors.electricViolet, XARColors.electricBlue, XARColors.electricCyan],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  public static let warmGlow = LinearGradient(
    colors: [XARColors.electricPink, XARColors.electricAmber],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  public static let coolGlow = LinearGradient(
    colors: [XARColors.electricCyan, XARColors.electricBlue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  public static let emeraldGlow = LinearGradient(
    colors: [XARColors.electricEmerald, XARColors.electricCyan],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  public static let voidFade = LinearGradient(
    colors: [XARColors.void, XARColors.surface],
    startPoint: .top,
    endPoint: .bottom
  )

  /// Radial glow for spotlight effects behind cards
  public static func spotlightGlow(_ accent: Color) -> RadialGradient {
    RadialGradient(
      colors: [accent.opacity(0.25), accent.opacity(0.05), .clear],
      center: .center,
      startRadius: 0,
      endRadius: 200
    )
  }
}

// MARK: - Shadow Presets

public enum XARShadows {
  static func glow(_ color: Color, radius: CGFloat = 20) -> some View {
    Color.clear
      .shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 4)
  }
}

// MARK: - Hex Color Extension

extension Color {
  init(hex: UInt, alpha: Double = 1.0) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }
}
