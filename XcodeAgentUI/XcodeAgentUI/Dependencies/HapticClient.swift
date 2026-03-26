import AppKit
import Dependencies
import Foundation

struct HapticClient: Sendable {
  var perform: @Sendable () -> Void

  init(perform: @escaping @Sendable () -> Void = {}) {
    self.perform = perform
  }
}

extension HapticClient: DependencyKey {
  static var liveValue: HapticClient {
    HapticClient(perform: {
      NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    })
  }

  static var testValue: HapticClient {
    HapticClient()
  }
}

extension DependencyValues {
  var hapticClient: HapticClient {
    get { self[HapticClient.self] }
    set { self[HapticClient.self] = newValue }
  }
}
