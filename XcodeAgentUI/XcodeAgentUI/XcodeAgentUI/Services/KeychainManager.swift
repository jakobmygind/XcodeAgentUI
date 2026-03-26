import Foundation
import Security

/// Manages API tokens in the macOS Keychain
struct KeychainManager {
  static let servicePrefix = "com.openclaw.xcode-agent-ui"

  enum TokenKey: String, CaseIterable, Codable {
    case githubToken = "github-token"
    case gitlabToken = "gitlab-token"
    case jiraToken = "jira-token"
    case jiraEmail = "jira-email"
    case shortcutToken = "shortcut-token"
    case telegramBotToken = "telegram-bot-token"
    case telegramChatID = "telegram-chat-id"

    var label: String {
      switch self {
      case .githubToken: return "Personal Access Token"
      case .gitlabToken: return "Access Token"
      case .jiraToken: return "API Token"
      case .jiraEmail: return "Email"
      case .shortcutToken: return "API Token"
      case .telegramBotToken: return "Bot Token"
      case .telegramChatID: return "Chat ID"
      }
    }

    var placeholder: String {
      switch self {
      case .githubToken: return "ghp_..."
      case .gitlabToken: return "glpat-..."
      case .jiraToken: return "Jira API token"
      case .jiraEmail: return "you@company.com"
      case .shortcutToken: return "Shortcut API token"
      case .telegramBotToken: return "123456:ABC-DEF..."
      case .telegramChatID: return "-1001234567890"
      }
    }
  }

  static func save(key: TokenKey, value: String) -> Bool {
    delete(key: key)

    guard let data = value.data(using: .utf8) else { return false }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: servicePrefix,
      kSecAttrAccount as String: key.rawValue,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]

    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
  }

  static func load(key: TokenKey) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: servicePrefix,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  @discardableResult
  static func delete(key: TokenKey) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: servicePrefix,
      kSecAttrAccount as String: key.rawValue,
    ]
    return SecItemDelete(query as CFDictionary) == errSecSuccess
  }

  static func hasValue(key: TokenKey) -> Bool {
    load(key: key) != nil
  }
}
