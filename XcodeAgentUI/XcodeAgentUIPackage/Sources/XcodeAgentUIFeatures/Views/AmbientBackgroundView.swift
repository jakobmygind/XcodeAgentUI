import SwiftUI
import XcodeAgentUICore

// MARK: - Ambient Breathing Background

/// A living, breathing background that subtly shifts colors and luminosity.
/// Creates the feeling that the UI is alive — like an organism at rest.
struct AmbientBreathingBackground: View {
  @State private var breathPhase: Double = 0
  @State private var colorShift: Double = 0

  let baseColor: Color
  let accentColor: Color
  let breathSpeed: Double

  init(
    base: Color = XARColors.void,
    accent: Color = XARColors.electricViolet,
    speed: Double = 8.0
  ) {
    self.baseColor = base
    self.accentColor = accent
    self.breathSpeed = speed
  }

  var body: some View {
    ZStack {
      // Deep void base
      baseColor.ignoresSafeArea()

      // Breathing gradient orb — top left
      RadialGradient(
        colors: [
          accentColor.opacity(0.08 + breathPhase * 0.04),
          accentColor.opacity(0.02),
          .clear,
        ],
        center: .topLeading,
        startRadius: 50,
        endRadius: 400 + breathPhase * 50
      )
      .ignoresSafeArea()

      // Counter-breathing orb — bottom right
      RadialGradient(
        colors: [
          XARColors.electricCyan.opacity(0.06 + colorShift * 0.03),
          XARColors.electricCyan.opacity(0.01),
          .clear,
        ],
        center: .bottomTrailing,
        startRadius: 30,
        endRadius: 350 + colorShift * 40
      )
      .ignoresSafeArea()

      // Subtle center warmth
      RadialGradient(
        colors: [
          XARColors.electricPink.opacity(0.03 + breathPhase * 0.02),
          .clear,
        ],
        center: .center,
        startRadius: 0,
        endRadius: 300
      )
      .ignoresSafeArea()
    }
    .onAppear {
      withAnimation(.easeInOut(duration: breathSpeed).repeatForever(autoreverses: true)) {
        breathPhase = 1.0
      }
      withAnimation(
        .easeInOut(duration: breathSpeed * 1.3).repeatForever(autoreverses: true).delay(1.5)
      ) {
        colorShift = 1.0
      }
    }
  }
}

// MARK: - Particle Field View

/// Floating particle system that creates depth and atmosphere.
/// Particles drift slowly upward with subtle parallax, like luminous dust motes.
struct ParticleFieldView: View {
  let particleCount: Int
  let baseColor: Color

  @State private var particles: [Particle] = []

  init(count: Int = 40, color: Color = XARColors.electricCyan) {
    self.particleCount = count
    self.baseColor = color
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        ForEach(particles) { particle in
          ParticleDot(particle: particle, color: baseColor)
        }
      }
      .onAppear {
        particles = (0..<particleCount).map { _ in
          Particle.random(in: geo.size)
        }
      }
    }
    .allowsHitTesting(false)
  }
}

private struct ParticleDot: View {
  let particle: Particle
  let color: Color

  @State private var animatedY: CGFloat = 0
  @State private var animatedOpacity: Double = 0

  var body: some View {
    Circle()
      .fill(color.opacity(animatedOpacity))
      .frame(width: particle.size, height: particle.size)
      .blur(radius: particle.size > 3 ? 1 : 0)
      .position(x: particle.x, y: animatedY)
      .onAppear {
        animatedY = particle.y
        animatedOpacity = 0

        // Fade in
        withAnimation(.easeIn(duration: particle.speed * 0.2).delay(particle.delay)) {
          animatedOpacity = particle.opacity
        }

        // Drift upward continuously
        withAnimation(
          .linear(duration: particle.speed)
          .repeatForever(autoreverses: false)
          .delay(particle.delay)
        ) {
          animatedY = -particle.size
        }
      }
  }
}

private struct Particle: Identifiable {
  let id = UUID()
  let x: CGFloat
  let y: CGFloat
  let size: CGFloat
  let opacity: Double
  let speed: Double
  let delay: Double

  static func random(in size: CGSize) -> Particle {
    Particle(
      x: CGFloat.random(in: 0...size.width),
      y: CGFloat.random(in: 0...size.height),
      size: CGFloat.random(in: 1.5...4.5),
      opacity: Double.random(in: 0.08...0.25),
      speed: Double.random(in: 15...35),
      delay: Double.random(in: 0...8)
    )
  }
}

// MARK: - Aurora Wave View

/// Slow-moving aurora waves that undulate across the background.
/// Creates an ethereal, Northern Lights-inspired atmosphere.
struct AuroraWaveView: View {
  @State private var wavePhase: Double = 0

  let colors: [Color]
  let speed: Double

  init(
    colors: [Color] = [
      XARColors.electricViolet.opacity(0.12),
      XARColors.electricCyan.opacity(0.08),
      XARColors.electricPink.opacity(0.06),
    ],
    speed: Double = 12.0
  ) {
    self.colors = colors
    self.speed = speed
  }

  var body: some View {
    ZStack {
      ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
        AuroraWavePath(
          phase: wavePhase + Double(index) * 0.7,
          amplitude: 40 + CGFloat(index) * 15,
          verticalOffset: CGFloat(index) * 80
        )
        .fill(color)
        .blur(radius: 30 + CGFloat(index) * 10)
      }
    }
    .onAppear {
      withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
        wavePhase = .pi * 2
      }
    }
    .allowsHitTesting(false)
  }
}

private struct AuroraWavePath: Shape {
  var phase: Double
  let amplitude: CGFloat
  let verticalOffset: CGFloat

  var animatableData: Double {
    get { phase }
    set { phase = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let midY = rect.midY + verticalOffset
    let steps = 80

    path.move(to: CGPoint(x: 0, y: rect.maxY))
    path.addLine(to: CGPoint(x: 0, y: midY))

    for step in 0...steps {
      let x = rect.width * CGFloat(step) / CGFloat(steps)
      let relX = CGFloat(step) / CGFloat(steps)
      let wave = sin(relX * .pi * 3 + phase) * amplitude
      let secondWave = sin(relX * .pi * 1.5 + phase * 0.7) * amplitude * 0.5
      let y = midY + wave + secondWave
      path.addLine(to: CGPoint(x: x, y: y))
    }

    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()

    return path
  }
}

// MARK: - Ambient Background Composite

/// Combines breathing, particles, and aurora into a single ambient background layer.
/// Drop this behind your main content for maximum atmosphere.
struct AmbientBackground: View {
  let style: Style

  enum Style {
    case minimal      // Breathing only — low GPU
    case standard     // Breathing + particles
    case cinematic    // Breathing + particles + aurora waves
  }

  var body: some View {
    ZStack {
      AmbientBreathingBackground()

      if style == .standard || style == .cinematic {
        ParticleFieldView(count: style == .cinematic ? 50 : 30)
      }

      if style == .cinematic {
        AuroraWaveView()
      }
    }
    .ignoresSafeArea()
  }
}

// MARK: - Preview

#Preview("Ambient Background - Cinematic") {
  ZStack {
    AmbientBackground(style: .cinematic)

    VStack(spacing: 20) {
      Text("Xcode Agent Runner")
        .font(.largeTitle.bold())
        .foregroundColor(XARColors.textPrimary)

      Text("Ambient atmosphere active")
        .font(.body)
        .foregroundColor(XARColors.textSecondary)
    }
    .padding(40)
    .glassmorphism()
  }
  .frame(width: 600, height: 400)
}
