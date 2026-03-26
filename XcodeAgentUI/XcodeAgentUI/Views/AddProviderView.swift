import SwiftUI

/// Form to add a new provider with type selection, connection details, and credentials
struct AddProviderView: View {
  @Environment(AgentService.self) var agentService
  @Environment(\.dismiss) private var dismiss

  @State private var selectedType: ProviderType = .github
  @State private var name: String = ""
  @State private var baseURL: String = ""
  @State private var defaultProject: String = ""
  @State private var tokenValues: [KeychainManager.TokenKey: String] = [:]
  @State private var showDuplicateWarning = false

  private var store: ProviderStore { agentService.providerStore }

  /// Types not yet configured
  private var availableTypes: [ProviderType] {
    let existingTypes = Set(store.providers.map(\.type))
    return ProviderType.allCases.filter { !existingTypes.contains($0) }
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("Add Provider")
        .font(.title2)
        .fontWeight(.bold)

      Form {
        Section("Provider Type") {
          if availableTypes.isEmpty {
            Label("All provider types are already configured.", systemImage: "checkmark.circle")
              .foregroundStyle(.secondary)
          } else {
            Picker("Type", selection: $selectedType) {
              ForEach(availableTypes, id: \.self) { type in
                HStack(spacing: 6) {
                  Image(systemName: type.icon)
                  Text(type.displayName)
                }
                .tag(type)
              }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: selectedType) { _, newType in
              applyDefaults(for: newType)
            }
          }
        }

        Section("Connection") {
          TextField("Display Name", text: $name)
            .textFieldStyle(.roundedBorder)
          TextField("Base URL", text: $baseURL)
            .textFieldStyle(.roundedBorder)
          TextField(selectedType.projectPlaceholder, text: $defaultProject)
            .textFieldStyle(.roundedBorder)
            .help("Default project used when assigning tickets")
        }

        Section("Credentials") {
          ForEach(selectedType.requiredCredentialKeys, id: \.rawValue) { key in
            HStack {
              Text(key.label)
                .frame(width: 120, alignment: .leading)
              SecureField(key.placeholder, text: binding(for: key))
                .textFieldStyle(.roundedBorder)
            }
          }

          if selectedType == .jira {
            Text("Jira requires both an email and API token.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal)

      if showDuplicateWarning {
        Label("A provider of this type already exists.", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Add Provider") { addProvider() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!isValid || availableTypes.isEmpty)
      }
      .padding(.horizontal)
    }
    .padding(.vertical, 20)
    .frame(width: 480)
    .onAppear {
      if let first = availableTypes.first {
        selectedType = first
        applyDefaults(for: first)
      }
    }
  }

  // MARK: - Helpers

  private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func applyDefaults(for type: ProviderType) {
    name = type.displayName
    baseURL = type.defaultBaseURL
    defaultProject = ""
    tokenValues = [:]
    showDuplicateWarning = store.providers.contains { $0.type == type }
  }

  private func binding(for key: KeychainManager.TokenKey) -> Binding<String> {
    Binding(
      get: { tokenValues[key] ?? "" },
      set: { tokenValues[key] = $0 }
    )
  }

  private func addProvider() {
    let provider = Provider(
      id: "\(selectedType.rawValue)-\(UUID().uuidString.prefix(8).lowercased())",
      name: name.trimmingCharacters(in: .whitespaces),
      type: selectedType,
      baseURL: baseURL.trimmingCharacters(in: .whitespaces),
      defaultProject: defaultProject.trimmingCharacters(in: .whitespaces)
    )

    // Save credentials to Keychain
    for (key, value) in tokenValues where !value.isEmpty {
      KeychainManager.save(key: key, value: value)
    }

    store.addProvider(provider)
    store.triggerObservationUpdate()
    dismiss()
  }
}
