import SwiftUI

struct TicketAssignView: View {
  @EnvironmentObject var agentService: AgentService
  @State private var assignment = TicketAssignment()
  @State private var isAssigning = false
  @State private var lastResult: String?

  private var connectedProviders: [Provider] {
    agentService.providerStore.connectedProviders
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        Text("Assign Ticket")
          .font(.largeTitle)
          .fontWeight(.bold)
          .frame(maxWidth: .infinity, alignment: .leading)

        if connectedProviders.isEmpty {
          noProvidersView
        } else {
          providerSection
          ticketSection
          agentSection
          assignButton
        }

        if let result = lastResult {
          GroupBox("Result") {
            Text(result)
              .font(.system(.body, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
          }
        }

        Spacer()
      }
      .padding()
    }
    .onAppear {
      if assignment.provider == nil, let first = connectedProviders.first {
        assignment.provider = first
        assignment.project = first.defaultProject
      }
    }
  }

  // MARK: - No Providers

  private var noProvidersView: some View {
    GroupBox {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.title)
          .foregroundStyle(.orange)
        Text("No providers connected")
          .font(.headline)
        Text("Add API credentials in Settings > Providers to connect a ticket source.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
    }
  }

  // MARK: - Provider Picker

  private var providerSection: some View {
    GroupBox("Ticket Source") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Provider", selection: $assignment.provider) {
          ForEach(connectedProviders) { provider in
            HStack(spacing: 6) {
              Image(systemName: provider.type.icon)
              Text(provider.name)
            }
            .tag(Optional(provider))
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: assignment.provider) { _, newProvider in
          if let provider = newProvider {
            assignment.project = provider.defaultProject
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Ticket Fields

  private var ticketSection: some View {
    GroupBox("Ticket Details") {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Project")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField(
            assignment.provider?.type.projectPlaceholder ?? "Project",
            text: $assignment.project
          )
          .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Ticket ID")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField(
            assignment.provider?.type.ticketPlaceholder ?? "Ticket ID",
            text: $assignment.ticketID
          )
          .textFieldStyle(.roundedBorder)
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Agent Config

  private var agentSection: some View {
    GroupBox("Agent Configuration") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Model", selection: $assignment.model) {
          ForEach(AgentModel.allCases) { model in
            HStack {
              Text(model.rawValue)
              Text("(\(model.label))")
                .foregroundStyle(.secondary)
            }
            .tag(model)
          }
        }
        .pickerStyle(.radioGroup)

        Text(assignment.model.description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Assign Button

  private var assignButton: some View {
    HStack {
      Button(action: assignTicket) {
        HStack {
          if isAssigning {
            ProgressView()
              .controlSize(.small)
          }
          Image(systemName: "play.fill")
          Text("Assign & Start")
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!isValid || isAssigning)

      Spacer()

      if !agentService.routerRunner.isRunning {
        Label("Router is not running", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .font(.caption)
      }
    }
  }

  // MARK: - Helpers

  private var isValid: Bool {
    assignment.provider != nil && !assignment.ticketID.trimmingCharacters(in: .whitespaces).isEmpty
      && !assignment.project.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func assignTicket() {
    guard let provider = assignment.provider else { return }
    isAssigning = true
    lastResult = nil
    agentService.assignTicket(assignment)

    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      isAssigning = false
      lastResult =
        "Ticket \(provider.type.rawValue):\(assignment.project)#\(assignment.ticketID) dispatched to worker with \(assignment.model.rawValue) model."
    }
  }
}
