import AppKit
import Dependencies
import DependenciesMacros
import Foundation

/// Client for macOS haptic feedback.
///
/// Provides tactile feedback for important UI events such as
/// acceptance criteria completion and ticket status changes.
@DependencyClient
struct HapticClient: Sendable {
  var perform: @Sendable () -> Void
}

extension HapticClient: DependencyKey {
  static var liveValue: HapticClient {
    HapticClient(perform: {
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    })
  }
}

extension DependencyValues {
  var hapticClient: HapticClient {
    get { self[HapticClient.self] }
    set { self[HapticClient.self] = newValue }
  }
}
