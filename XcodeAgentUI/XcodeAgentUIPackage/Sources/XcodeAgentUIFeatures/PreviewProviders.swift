import SwiftUI
import XcodeAgentUICore

// MARK: - Preview Environment Wrapper

/// Wraps any view with a fully mocked environment for SwiftUI previews.
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

enum PreviewConfig {
  static func window<V: View>(_ view: V) -> some View {
    view
      .frame(width: 1100, height: 750)
      .background(XARColors.void)
      .preferredColorScheme(.dark)
  }

  static func card<V: View>(_ view: V) -> some View {
    view
      .padding(24)
      .background(XARColors.surface)
      .preferredColorScheme(.dark)
  }

  static func panel<V: View>(_ view: V) -> some View {
    view
      .frame(width: 800, height: 600)
      .background(XARColors.void)
      .preferredColorScheme(.dark)
  }
}

// Preview macros intentionally omitted from SwiftPM build.
