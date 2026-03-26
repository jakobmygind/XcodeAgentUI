import Combine
import Foundation

/// Manages provider configuration and credential status
class ProviderStore: ObservableObject {
  @Published var providers: [Provider] = []

  private static let storageKey = "configuredProviders"

  init() {
    loadProviders()
  }

  // MARK: - Computed Properties

  var connectedProviders: [Provider] {
    providers.filter { $0.isConnected }
  }

  var disconnectedProviders: [Provider] {
    providers.filter { !$0.isConnected }
  }

  func provider(for type: ProviderType) -> Provider? {
    providers.first { $0.type == type }
  }

  // MARK: - CRUD

  func addProvider(_ provider: Provider) {
    guard !providers.contains(where: { $0.id == provider.id }) else { return }
    providers.append(provider)
    save()
  }

  func updateProvider(_ provider: Provider) {
    guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
    providers[index] = provider
    save()
  }

  func removeProvider(_ provider: Provider) {
    // Remove credentials from Keychain
    for key in provider.type.requiredCredentialKeys {
      KeychainManager.delete(key: key)
    }
    providers.removeAll { $0.id == provider.id }
    save()
  }

  /// Refresh connection status for all providers (re-checks Keychain)
  func refreshStatus() {
    objectWillChange.send()
  }

  // MARK: - Persistence

  private func save() {
    if let data = try? JSONEncoder().encode(providers) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }

  private func loadProviders() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let saved = try? JSONDecoder().decode([Provider].self, from: data)
    {
      providers = saved
    } else {
      // First launch: seed with default providers
      providers = ProviderType.allCases.map { Provider.defaultProvider(for: $0) }
      save()
    }
  }

  // MARK: - Environment Variables

  /// Build environment variables for all connected providers
  func buildProviderEnvironment() -> [String: String] {
    var env: [String: String] = [:]

    if let token = KeychainManager.load(key: .githubToken) {
      env["GITHUB_TOKEN"] = token
    }
    if let token = KeychainManager.load(key: .gitlabToken) {
      env["GITLAB_TOKEN"] = token
    }
    if let token = KeychainManager.load(key: .jiraToken) {
      env["JIRA_API_TOKEN"] = token
    }
    if let email = KeychainManager.load(key: .jiraEmail) {
      env["JIRA_EMAIL"] = email
    }
    if let token = KeychainManager.load(key: .shortcutToken) {
      env["SHORTCUT_API_TOKEN"] = token
    }
    if let token = KeychainManager.load(key: .telegramBotToken) {
      env["TELEGRAM_BOT_TOKEN"] = token
    }
    if let chatID = KeychainManager.load(key: .telegramChatID) {
      env["TELEGRAM_CHAT_ID"] = chatID
    }

    return env
  }
}
