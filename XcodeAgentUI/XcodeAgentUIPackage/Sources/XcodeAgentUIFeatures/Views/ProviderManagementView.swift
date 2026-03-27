import SwiftUI
import XcodeAgentUICore

/// Lists all configured providers with status, edit, and delete controls
public struct ProviderManagementView: View {
  public init() {}

  @Environment(AgentService.self) var agentService
  @State private var showAddSheet = false
  @State private var editingProvider: Provider?
  @State private var providerToDelete: Provider?

  private var store: ProviderStore { agentService.providerStore }

  public var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        header
        connectedSection
        disconnectedSection
        Spacer()
      }
      .padding()
    }
    .onAppear { store.triggerObservationUpdate() }
    .sheet(isPresented: $showAddSheet) {
      AddProviderView()
        .environment(agentService)
    }
    .sheet(item: $editingProvider) { provider in
      EditProviderSheet(provider: provider)
        .environment(agentService)
    }
    .alert("Remove Provider?", isPresented: .init(
      get: { providerToDelete != nil },
      set: { if !$0 { providerToDelete = nil } }
    )) {
      Button("Cancel", role: .cancel) { providerToDelete = nil }
      Button("Remove", role: .destructive) {
        if let provider = providerToDelete {
          store.removeProvider(provider)
          providerToDelete = nil
        }
      }
    } message: {
      if let provider = providerToDelete {
        Text("This will remove \(provider.name) and delete its credentials from the Keychain.")
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("Providers")
          .font(.largeTitle)
          .fontWeight(.bold)
        Text("\(store.connectedProviders.count) connected, \(store.disconnectedProviders.count) pending")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: { showAddSheet = true }) {
        Label("Add Provider", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.regular)
    }
  }

  // MARK: - Connected

  @ViewBuilder
  private var connectedSection: some View {
    if !store.connectedProviders.isEmpty {
      GroupBox {
        VStack(spacing: 0) {
          ForEach(store.connectedProviders) { provider in
            providerRow(provider)
            if provider.id != store.connectedProviders.last?.id {
              Divider().padding(.horizontal, 8)
            }
          }
        }
      } label: {
        Label("Connected", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
  }

  // MARK: - Disconnected

  @ViewBuilder
  private var disconnectedSection: some View {
    if !store.disconnectedProviders.isEmpty {
      GroupBox {
        VStack(spacing: 0) {
          ForEach(store.disconnectedProviders) { provider in
            providerRow(provider)
            if provider.id != store.disconnectedProviders.last?.id {
              Divider().padding(.horizontal, 8)
            }
          }
        }
      } label: {
        Label("Not Connected", systemImage: "xmark.circle")
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Row

  private func providerRow(_ provider: Provider) -> some View {
    HStack(spacing: 12) {
      Image(systemName: provider.type.icon)
        .font(.title2)
        .foregroundStyle(provider.isConnected ? .primary : .secondary)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(provider.name)
          .fontWeight(.medium)
        Text(provider.baseURL)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if !provider.defaultProject.isEmpty {
          Text(provider.defaultProject)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }

      Spacer()

      // Credential status badges
      credentialBadges(for: provider)

      // Actions
      Button(action: { editingProvider = provider }) {
        Image(systemName: "pencil")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Button(action: { providerToDelete = provider }) {
        Image(systemName: "trash")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .tint(.red)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 4)
  }

  private func credentialBadges(for provider: Provider) -> some View {
    HStack(spacing: 4) {
      ForEach(provider.type.requiredCredentialKeys, id: \.rawValue) { key in
        let hasValue = KeychainManager.hasValue(key: key)
        HStack(spacing: 2) {
          Image(systemName: hasValue ? "key.fill" : "key")
            .font(.caption2)
          Text(key.label)
            .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(hasValue ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .foregroundStyle(hasValue ? .green : .red)
        .clipShape(Capsule())
      }
    }
  }
}

// MARK: - Edit Provider Sheet

struct EditProviderSheet: View {
  @Environment(AgentService.self) var agentService
  @Environment(\.dismiss) private var dismiss

  let provider: Provider
  @State private var name: String = ""
  @State private var baseURL: String = ""
  @State private var defaultProject: String = ""
  @State private var tokenValues: [KeychainManager.TokenKey: String] = [:]

  public var body: some View {
    VStack(spacing: 16) {
      HStack {
        Image(systemName: provider.type.icon)
          .font(.title2)
        Text("Edit \(provider.type.displayName)")
          .font(.title2)
          .fontWeight(.bold)
      }

      Form {
        Section("Connection") {
          TextField("Display Name", text: $name)
            .textFieldStyle(.roundedBorder)
          TextField("Base URL", text: $baseURL)
            .textFieldStyle(.roundedBorder)
          TextField(provider.type.projectPlaceholder, text: $defaultProject)
            .textFieldStyle(.roundedBorder)
        }

        Section("Credentials") {
          ForEach(provider.type.requiredCredentialKeys, id: \.rawValue) { key in
            HStack {
              Text(key.label)
                .frame(width: 120, alignment: .leading)
              SecureField(key.placeholder, text: binding(for: key))
                .textFieldStyle(.roundedBorder)
              if KeychainManager.hasValue(key: key) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
              }
            }
          }
          Text("Leave blank to keep existing credentials.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal)

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save") { saveChanges() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.horizontal)
    }
    .padding(.vertical, 20)
    .frame(width: 480)
    .onAppear {
      name = provider.name
      baseURL = provider.baseURL
      defaultProject = provider.defaultProject
    }
  }

  private func binding(for key: KeychainManager.TokenKey) -> Binding<String> {
    Binding(
      get: { tokenValues[key] ?? "" },
      set: { tokenValues[key] = $0 }
    )
  }

  private func saveChanges() {
    var updated = provider
    updated.name = name.trimmingCharacters(in: .whitespaces)
    updated.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
    updated.defaultProject = defaultProject.trimmingCharacters(in: .whitespaces)
    agentService.providerStore.updateProvider(updated)

    // Save non-empty credentials
    for (key, value) in tokenValues where !value.isEmpty {
      KeychainManager.save(key: key, value: value)
    }

    agentService.providerStore.triggerObservationUpdate()
    dismiss()
  }
}
