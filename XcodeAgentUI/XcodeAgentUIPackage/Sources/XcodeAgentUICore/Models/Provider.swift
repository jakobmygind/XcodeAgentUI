import Foundation

/// Type of ticket/issue provider
public enum ProviderType: String, Codable, CaseIterable, Identifiable {
  case github
  case gitlab
  case jira
  case shortcut

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .github: return "GitHub"
    case .gitlab: return "GitLab"
    case .jira: return "Jira"
    case .shortcut: return "Shortcut"
    }
  }

  public var icon: String {
    switch self {
    case .github: return "cat.fill"
    case .gitlab: return "globe"
    case .jira: return "ticket"
    case .shortcut: return "bolt.fill"
    }
  }

  public var defaultBaseURL: String {
    switch self {
    case .github: return "https://api.github.com"
    case .gitlab: return "https://gitlab.com/api/v4"
    case .jira: return "https://your-domain.atlassian.net"
    case .shortcut: return "https://api.app.shortcut.com"
    }
  }

  public var tokenPlaceholder: String {
    switch self {
    case .github: return "ghp_..."
    case .gitlab: return "glpat-..."
    case .jira: return "Jira API token"
    case .shortcut: return "Shortcut API token"
    }
  }

  public var projectPlaceholder: String {
    switch self {
    case .github: return "owner/repo"
    case .gitlab: return "group/project"
    case .jira: return "PROJECT_KEY"
    case .shortcut: return "workspace/project"
    }
  }

  public var ticketPlaceholder: String {
    switch self {
    case .github: return "Issue #"
    case .gitlab: return "Issue #"
    case .jira: return "PROJ-123"
    case .shortcut: return "Story ID"
    }
  }

  /// Keychain keys required for this provider
  public var requiredCredentialKeys: [KeychainManager.TokenKey] {
    switch self {
    case .github: return [.githubToken]
    case .gitlab: return [.gitlabToken]
    case .jira: return [.jiraToken, .jiraEmail]
    case .shortcut: return [.shortcutToken]
    }
  }
}

/// A configured provider instance
public struct Provider: Identifiable, Codable, Hashable {
  public let id: String
  public var name: String
  public var type: ProviderType
  public var baseURL: String
  public var defaultProject: String

  public init(
    id: String,
    name: String,
    type: ProviderType,
    baseURL: String,
    defaultProject: String
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.baseURL = baseURL
    self.defaultProject = defaultProject
  }

  /// Whether this provider has valid credentials in the Keychain
  public var isConnected: Bool {
    type.requiredCredentialKeys.allSatisfy { KeychainManager.hasValue(key: $0) }
  }

  public static func defaultProvider(for type: ProviderType) -> Provider {
    Provider(
      id: type.rawValue,
      name: type.displayName,
      type: type,
      baseURL: type.defaultBaseURL,
      defaultProject: ""
    )
  }
}

/// A credential bound to a provider
struct Credential: Identifiable {
  let id: String
  let providerID: String
  let key: KeychainManager.TokenKey
  var hasValue: Bool

  var label: String { key.label }
  var placeholder: String { key.placeholder }
}
