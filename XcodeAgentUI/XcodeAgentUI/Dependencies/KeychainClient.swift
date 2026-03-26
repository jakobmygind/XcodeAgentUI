import Dependencies
import Foundation

struct KeychainClient: Sendable {
  var save: @Sendable (_ key: KeychainManager.TokenKey, _ value: String) -> Bool
  var load: @Sendable (_ key: KeychainManager.TokenKey) -> String?
  var delete: @Sendable (_ key: KeychainManager.TokenKey) -> Bool
  var hasValue: @Sendable (_ key: KeychainManager.TokenKey) -> Bool

  init(
    save: @escaping @Sendable (_ key: KeychainManager.TokenKey, _ value: String) -> Bool = { _, _ in false },
    load: @escaping @Sendable (_ key: KeychainManager.TokenKey) -> String? = { _ in nil },
    delete: @escaping @Sendable (_ key: KeychainManager.TokenKey) -> Bool = { _ in false },
    hasValue: @escaping @Sendable (_ key: KeychainManager.TokenKey) -> Bool = { _ in false }
  ) {
    self.save = save
    self.load = load
    self.delete = delete
    self.hasValue = hasValue
  }
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

  static var testValue: KeychainClient {
    KeychainClient()
  }
}

extension DependencyValues {
  var keychainClient: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}
