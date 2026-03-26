import SwiftUI

struct SettingsView: View {
  @Environment(AgentService.self) var agentService

  var body: some View {
    TabView {
      GeneralSettingsView()
        .environment(agentService)
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      TokenSettingsView()
        .tabItem {
          Label("API Tokens", systemImage: "key")
        }

      ProviderSettingsView()
        .environment(agentService)
        .tabItem {
          Label("Providers", systemImage: "cloud.fill")
        }

      PortSettingsView()
        .environment(agentService)
        .tabItem {
          Label("Ports", systemImage: "network")
        }

      NotificationSettingsView()
        .tabItem {
          Label("Notifications", systemImage: "bell.badge")
        }
    }
    .frame(width: 600, height: 520)
  }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
  @Environment(AgentService.self) var agentService
  @State private var directoryPath: String = ""

  var body: some View {
    Form {
      Section("Agent Directory") {
        HStack {
          TextField("Path to xcode-agent", text: $directoryPath)
            .textFieldStyle(.roundedBorder)
          Button("Browse...") { browseDirectory() }
        }
        Text("The directory containing the xcode-agent Node.js project.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .onAppear {
      directoryPath = agentService.agentDirectory
    }
    .onChange(of: directoryPath) { _, newValue in
      agentService.agentDirectory = newValue
    }
  }

  private func browseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Select the xcode-agent project directory"

    if panel.runModal() == .OK, let url = panel.url {
      directoryPath = url.path
    }
  }
}

// MARK: - Token Settings

struct TokenSettingsView: View {
  var body: some View {
    Form {
      Section("GitHub") {
        TokenField(key: .githubToken, label: "Personal Access Token", placeholder: "ghp_...")
      }
      Section("GitLab") {
        TokenField(key: .gitlabToken, label: "Access Token", placeholder: "glpat-...")
      }
      Section("Jira") {
        TokenField(key: .jiraEmail, label: "Email", placeholder: "you@company.com")
        TokenField(key: .jiraToken, label: "API Token", placeholder: "Jira API token")
      }
      Section("Shortcut") {
        TokenField(key: .shortcutToken, label: "API Token", placeholder: "Shortcut API token")
      }
      Section("Telegram") {
        TokenField(key: .telegramBotToken, label: "Bot Token", placeholder: "123456:ABC-DEF...")
        TokenField(key: .telegramChatID, label: "Chat ID", placeholder: "-1001234567890")
      }
    }
    .padding()
  }
}

struct TokenField: View {
  let key: KeychainManager.TokenKey
  let label: String
  let placeholder: String

  @State private var value: String = ""
  @State private var hasValue: Bool = false
  @State private var isEditing: Bool = false
  @State private var saved: Bool = false

  var body: some View {
    HStack {
      if isEditing {
        SecureField(placeholder, text: $value)
          .textFieldStyle(.roundedBorder)
        Button("Save") {
          if KeychainManager.save(key: key, value: value) {
            hasValue = true
            isEditing = false
            saved = true
            value = ""
            Task { try? await Task.sleep(for: .seconds(2)); saved = false }
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        Button("Cancel") {
          isEditing = false
          value = ""
        }
        .controlSize(.small)
      } else {
        Text(label)
        Spacer()
        if hasValue {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Text("Stored in Keychain")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Update") { isEditing = true }
            .controlSize(.small)
          Button("Remove") {
            KeychainManager.delete(key: key)
            hasValue = false
          }
          .controlSize(.small)
          .foregroundStyle(.red)
        } else {
          Image(systemName: "xmark.circle")
            .foregroundStyle(.secondary)
          Text("Not set")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Set") { isEditing = true }
            .controlSize(.small)
        }
      }

      if saved {
        Image(systemName: "checkmark")
          .foregroundStyle(.green)
          .transition(.opacity)
      }
    }
    .onAppear {
      hasValue = KeychainManager.hasValue(key: key)
    }
  }
}

// MARK: - Port Settings

// MARK: - Provider Settings (Settings tab variant)

struct ProviderSettingsView: View {
  @Environment(AgentService.self) var agentService

  private var store: ProviderStore { agentService.providerStore }

  var body: some View {
    Form {
      Section("Connected Providers") {
        if store.connectedProviders.isEmpty {
          Text("No providers connected yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(store.connectedProviders) { provider in
            HStack(spacing: 8) {
              Image(systemName: provider.type.icon)
              Text(provider.name)
              Spacer()
              Text(provider.baseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }
        }
      }

      Section {
        Text("Use the **Providers** sidebar tab for full management (add, edit, delete).")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .onAppear { store.triggerObservationUpdate() }
  }
}

// MARK: - Port Settings

struct PortSettingsView: View {
  @Environment(AgentService.self) var agentService
  @State private var routerPortStr: String = ""
  @State private var bridgePortStr: String = ""

  var body: some View {
    Form {
      Section("Router") {
        TextField("Port", text: $routerPortStr)
          .textFieldStyle(.roundedBorder)
        Text("Default: 3800. The webhook receiver port.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Bridge") {
        TextField("Port", text: $bridgePortStr)
          .textFieldStyle(.roundedBorder)
        Text("Default: 9300. The WebSocket bridge port.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .onAppear {
      routerPortStr = "\(agentService.routerPort)"
      bridgePortStr = "\(agentService.bridgePort)"
    }
    .onChange(of: routerPortStr) { _, newValue in
      if let port = Int(newValue), port > 0, port < 65536 {
        agentService.routerPort = port
      }
    }
    .onChange(of: bridgePortStr) { _, newValue in
      if let port = Int(newValue), port > 0, port < 65536 {
        agentService.bridgePort = port
      }
    }
  }
}
