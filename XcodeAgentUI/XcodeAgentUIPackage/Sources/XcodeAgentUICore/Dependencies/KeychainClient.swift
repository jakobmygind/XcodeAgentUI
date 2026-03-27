import Dependencies
import DependenciesMacros
import Foundation

/// Client for secure credential storage via the macOS Keychain.
///
/// Wraps `KeychainManager` (Security framework) for dependency injection,
/// enabling deterministic testing of code that reads or writes API tokens.
@DependencyClient
struct KeychainClient: Sendable {
  var save: @Sendable (_ key: KeychainManager.TokenKey, _ value: String) -> Bool = { _, _ in false }
  var load: @Sendable (_ key: KeychainManager.TokenKey) -> String?
  var delete: @Sendable (_ key: KeychainManager.TokenKey) -> Bool = { _ in false }
  var hasValue: @Sendable (_ key: KeychainManager.TokenKey) -> Bool = { _ in false }
}

extension KeychainClient: DependencyKey {
  static var liveValue: KeychainClient {
    KeychainClient(
      save: { KeychainManager.save(key: $0, value: $1) },
      load: { KeychainManager.load(key: $0) },
      delete: { KeychainManager.delete(key: $0) },
      hasValue: { KeychainManager.hasValue(key: $0) }
    )
  }
}

extension DependencyValues {
  var keychainClient: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}
