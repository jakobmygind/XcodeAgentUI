import Dependencies
import Foundation
import Observation

@Observable @MainActor
public final class ProviderStore {
  public var providers: [Provider] = []

  @ObservationIgnored @Dependency(\.keychainClient) var keychainClient

  private static let storageKey = "configuredProviders"

  public init() {
    loadProviders()
  }

  // MARK: - Computed Properties

  public var connectedProviders: [Provider] {
    providers.filter { $0.isConnected }
  }

  public var disconnectedProviders: [Provider] {
    providers.filter { !$0.isConnected }
  }

  public func provider(for type: ProviderType) -> Provider? {
    providers.first { $0.type == type }
  }

  // MARK: - CRUD

  public func addProvider(_ provider: Provider) {
    guard !providers.contains(where: { $0.id == provider.id }) else { return }
    providers.append(provider)
    save()
  }

  public func updateProvider(_ provider: Provider) {
    guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
    providers[index] = provider
    save()
  }

  public func removeProvider(_ provider: Provider) {
    for key in provider.type.requiredCredentialKeys {
      keychainClient.delete(key)
    }
    providers.removeAll { $0.id == provider.id }
    save()
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
      providers = ProviderType.allCases.map { Provider.defaultProvider(for: $0) }
      save()
    }
  }

  // MARK: - Observation Trigger

  public func triggerObservationUpdate() {
    let current = providers
    providers = current
  }

  // MARK: - Environment Variables

  public func buildProviderEnvironment() -> [String: String] {
    var env: [String: String] = [:]

    if let token = keychainClient.load(.githubToken) {
      env["GITHUB_TOKEN"] = token
    }
    if let token = keychainClient.load(.gitlabToken) {
      env["GITLAB_TOKEN"] = token
    }
    if let token = keychainClient.load(.jiraToken) {
      env["JIRA_API_TOKEN"] = token
    }
    if let email = keychainClient.load(.jiraEmail) {
      env["JIRA_EMAIL"] = email
    }
    if let token = keychainClient.load(.shortcutToken) {
      env["SHORTCUT_API_TOKEN"] = token
    }
    if let token = keychainClient.load(.telegramBotToken) {
      env["TELEGRAM_BOT_TOKEN"] = token
    }
    if let chatID = keychainClient.load(.telegramChatID) {
      env["TELEGRAM_CHAT_ID"] = chatID
    }

    return env
  }
}
