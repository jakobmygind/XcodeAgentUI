import SwiftUI

// MARK: - Preview Environment Wrapper

/// Wraps any view with a fully mocked environment for SwiftUI previews.
/// Usage:
/// ```swift
/// #Preview {
///   PreviewWrapper {
///     MissionControlView()
///   }
/// }
/// ```
struct PreviewWrapper<Content: View>: View {
  @State private var mockService = MockAgentService()
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .environment(mockService as AgentService)
      .frame(minWidth: 800, minHeight: 500)
      .background(AmbientBackground(style: .minimal))
  }
}

// MARK: - Preview Helpers

/// Quick-access preview configurations for common view testing scenarios.
enum PreviewConfig {

  /// Dark window chrome matching the production app
  static func window<V: View>(_ view: V) -> some View {
    view
      .frame(width: 1100, height: 750)
      .background(XARColors.void)
      .preferredColorScheme(.dark)
  }

  /// Compact card preview — for testing individual components
  static func card<V: View>(_ view: V) -> some View {
    view
      .padding(24)
      .background(XARColors.surface)
      .preferredColorScheme(.dark)
  }

  /// Full-width panel preview — for testing detail views
  static func panel<V: View>(_ view: V) -> some View {
    view
      .frame(width: 800, height: 600)
      .background(XARColors.void)
      .preferredColorScheme(.dark)
  }
}

// MARK: - Component Previews

#Preview("Mission Control") {
  PreviewWrapper {
    MissionControlView()
  }
  .preferredColorScheme(.dark)
}

#Preview("Queue View") {
  PreviewWrapper {
    QueueView()
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard") {
  PreviewWrapper {
    DashboardView()
  }
  .preferredColorScheme(.dark)
}

#Preview("Workload") {
  PreviewWrapper {
    WorkloadView()
  }
  .preferredColorScheme(.dark)
}

#Preview("Motion Showcase") {
  PreviewConfig.window(
    ZStack {
      AmbientBackground(style: .cinematic)

      VStack(spacing: 24) {
        Text("Motion Design System")
          .font(.largeTitle.bold())
          .foregroundColor(XARColors.textPrimary)
          .springEntrance(.scale)

        HStack(spacing: 16) {
          ForEach(0..<4) { i in
            VStack {
              RoundedRectangle(cornerRadius: 12)
                .fill(XARColors.electricViolet.opacity(0.3))
                .frame(width: 120, height: 80)
                .glassmorphism()
                .jellyHover()

              Text("Card \(i + 1)")
                .font(.caption)
                .foregroundColor(XARColors.textSecondary)
            }
            .staggeredAppear(index: i)
          }
        }

        HStack(spacing: 12) {
          Button("Elastic Light") {}
            .buttonStyle(ElasticButtonStyle(intensity: .light))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(XARColors.electricCyan.opacity(0.2))
            .clipShape(Capsule())

          Button("Elastic Heavy") {}
            .buttonStyle(ElasticButtonStyle(intensity: .heavy))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(XARColors.electricPink.opacity(0.2))
            .clipShape(Capsule())
        }
        .foregroundColor(XARColors.textPrimary)
      }
      .padding(40)
    }
  )
}
