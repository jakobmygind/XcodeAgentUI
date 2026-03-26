import SwiftUI

/// Standalone view for starting an interactive agent session with connected providers prefilled
struct StartSessionView: View {
  @Environment(AgentService.self) var agentService
  @Environment(\.dismiss) private var dismiss

  @Binding var selectedProvider: Provider?
  @Binding var project: String
  @Binding var ticketID: String
  @Binding var selectedModel: AgentModel
  @Binding var criteriaText: String

  let onStart: () -> Void

  private var connected: [Provider] {
    agentService.providerStore.connectedProviders
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("Start Agent Session")
        .font(.title2)
        .fontWeight(.bold)

      Form {
        providerSection
        ticketSection
        agentSection
        criteriaSection
      }
      .padding(.horizontal)

      actionBar
    }
    .padding(.vertical, 20)
    .frame(width: 500)
    .onAppear {
      if selectedProvider == nil, let first = connected.first {
        selectedProvider = first
        project = first.defaultProject
      }
    }
  }

  // MARK: - Provider

  private var providerSection: some View {
    Section("Provider") {
      if connected.isEmpty {
        Label("No providers connected", systemImage: "xmark.circle")
          .foregroundStyle(.secondary)
        Text("Add credentials in Settings > Providers to connect a ticket source.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Picker("Provider", selection: $selectedProvider) {
          ForEach(connected) { provider in
            HStack(spacing: 6) {
              Image(systemName: provider.type.icon)
              Text(provider.name)
              if provider.isConnected {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption2)
              }
            }
            .tag(Optional(provider))
          }
        }
        .pickerStyle(.radioGroup)
        .onChange(of: selectedProvider) { _, newProvider in
          if let provider = newProvider {
            project = provider.defaultProject
          }
        }
      }
    }
  }

  // MARK: - Ticket

  private var ticketSection: some View {
    Section("Ticket") {
      TextField(
        selectedProvider?.type.projectPlaceholder ?? "Project",
        text: $project
      )
      .textFieldStyle(.roundedBorder)

      TextField(
        selectedProvider?.type.ticketPlaceholder ?? "Ticket ID",
        text: $ticketID
      )
      .textFieldStyle(.roundedBorder)
    }
  }

  // MARK: - Agent

  private var agentSection: some View {
    Section("Agent") {
      Picker("Model", selection: $selectedModel) {
        ForEach(AgentModel.allCases) { model in
          Text("\(model.rawValue) (\(model.label))").tag(model)
        }
      }
      .pickerStyle(.radioGroup)

      Text(selectedModel.description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Criteria

  private var criteriaSection: some View {
    Section {
      VStack(alignment: .leading) {
        Text("Acceptance Criteria (one per line)")
          .font(.caption)
          .foregroundColor(.secondary)
        TextEditor(text: $criteriaText)
          .font(.system(.body, design: .monospaced))
          .frame(height: 100)
          .border(Color.secondary.opacity(0.3))
      }
    }
  }

  // MARK: - Actions

  private var actionBar: some View {
    HStack {
      Button("Cancel") { dismiss() }
        .keyboardShortcut(.cancelAction)

      Spacer()

      if agentService.bridgeStatus.state != .running {
        Label("Bridge not running", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      Button("Start") {
        onStart()
        dismiss()
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        ticketID.trimmingCharacters(in: .whitespaces).isEmpty
          || selectedProvider == nil
      )
      .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal)
  }
}
