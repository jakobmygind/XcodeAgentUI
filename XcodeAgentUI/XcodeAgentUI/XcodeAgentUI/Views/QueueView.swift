import SwiftUI

struct QueueView: View {
  @EnvironmentObject var agentService: AgentService
  @State private var showAddSheet = false
  @State private var showSettingsSheet = false
  @State private var filterStatus: QueueTicket.Status? = nil
  @State private var draggedTicket: QueueTicket?

  private var queueManager: QueueManager { agentService.queueManager }

  var body: some View {
    VStack(spacing: 0) {
      headerBar
      Divider()
      concurrencyBar
      Divider()
      filterBar
      Divider()
      ticketList
    }
    .sheet(isPresented: $showAddSheet) {
      AddToQueueSheet()
        .environmentObject(agentService)
    }
    .sheet(isPresented: $showSettingsSheet) {
      QueueSettingsSheet()
        .environmentObject(agentService)
    }
  }

  // MARK: - Header

  private var headerBar: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Queue Management")
          .font(.title2.bold())
        Text(
          "\(queueManager.pendingCount) pending \u{2022} \(queueManager.runningCount) running \u{2022} \(queueManager.pausedCount) paused"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      Button(action: { queueManager.processQueue() }) {
        Label("Process Queue", systemImage: "play.circle")
      }
      .help("Dispatch pending tickets to available agents")

      Button(action: { showSettingsSheet = true }) {
        Label("Settings", systemImage: "slider.horizontal.3")
      }

      Button(action: { showAddSheet = true }) {
        Label("Add Ticket", systemImage: "plus.circle.fill")
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }

  // MARK: - Concurrency Bar

  private var concurrencyBar: some View {
    HStack(spacing: 16) {
      ConcurrencyGauge(
        label: "Sonnet",
        current: queueManager.runningSonnetCount,
        max: queueManager.concurrencyLimits.maxSonnet,
        color: .blue
      )
      ConcurrencyGauge(
        label: "Opus",
        current: queueManager.runningOpusCount,
        max: queueManager.concurrencyLimits.maxOpus,
        color: .purple
      )
      Spacer()
      HStack(spacing: 4) {
        Text("Limits:")
          .font(.caption)
          .foregroundStyle(.secondary)
        Stepper(
          "Sonnet: \(queueManager.concurrencyLimits.maxSonnet)",
          value: Binding(
            get: { queueManager.concurrencyLimits.maxSonnet },
            set: { queueManager.concurrencyLimits.maxSonnet = $0 }
          ),
          in: 0...5
        )
        .font(.caption)
        Stepper(
          "Opus: \(queueManager.concurrencyLimits.maxOpus)",
          value: Binding(
            get: { queueManager.concurrencyLimits.maxOpus },
            set: { queueManager.concurrencyLimits.maxOpus = $0 }
          ),
          in: 0...3
        )
        .font(.caption)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  // MARK: - Filter Bar

  private var filterBar: some View {
    HStack(spacing: 6) {
      FilterChip(label: "All", count: queueManager.tickets.count, isSelected: filterStatus == nil) {
        filterStatus = nil
      }
      FilterChip(
        label: "Pending", count: queueManager.pendingCount,
        isSelected: filterStatus == .pending
      ) {
        filterStatus = .pending
      }
      FilterChip(
        label: "Running", count: queueManager.runningCount,
        isSelected: filterStatus == .running
      ) {
        filterStatus = .running
      }
      FilterChip(
        label: "Paused", count: queueManager.pausedCount,
        isSelected: filterStatus == .paused
      ) {
        filterStatus = .paused
      }
      FilterChip(
        label: "Done", count: queueManager.completedCount,
        isSelected: filterStatus == .completed
      ) {
        filterStatus = .completed
      }

      Spacer()

      if queueManager.completedCount > 0 {
        Button("Clear Done") {
          queueManager.clearCompleted()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 6)
  }

  // MARK: - Ticket List

  private var filteredTickets: [QueueTicket] {
    guard let filter = filterStatus else { return queueManager.tickets }
    if filter == .completed {
      return queueManager.tickets.filter { $0.status == .completed || $0.status == .failed }
    }
    return queueManager.tickets.filter { $0.status == filter }
  }

  private var ticketList: some View {
    Group {
      if filteredTickets.isEmpty {
        emptyState
      } else {
        List {
          ForEach(filteredTickets) { ticket in
            QueueTicketRow(ticket: ticket, queueManager: queueManager)
              .onDrag {
                draggedTicket = ticket
                return NSItemProvider(object: ticket.id.uuidString as NSString)
              }
              .onDrop(
                of: [.text],
                delegate: TicketDropDelegate(
                  ticket: ticket,
                  draggedTicket: $draggedTicket,
                  queueManager: queueManager
                )
              )
          }
          .onMove { source, destination in
            queueManager.moveTicket(from: source, to: destination)
          }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "tray")
        .font(.system(size: 48))
        .foregroundStyle(.tertiary)
      Text("No tickets in queue")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("Add tickets to the queue to manage agent workload")
        .font(.caption)
        .foregroundStyle(.tertiary)
      Button("Add Ticket") { showAddSheet = true }
        .buttonStyle(.borderedProminent)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Queue Ticket Row

struct QueueTicketRow: View {
  let ticket: QueueTicket
  @ObservedObject var queueManager: QueueManager

  var body: some View {
    HStack(spacing: 12) {
      // Drag handle
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.tertiary)
        .font(.caption)

      // Priority indicator
      priorityBadge

      // Ticket info
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(ticket.ticketID)
            .font(.headline.monospaced())
          Text(ticket.project)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary)
            .clipShape(Capsule())
        }
        HStack(spacing: 8) {
          Label(ticket.model, systemImage: ticket.model == "Opus" ? "brain.head.profile" : "bolt")
            .font(.caption)
            .foregroundStyle(ticket.model == "Opus" ? .purple : .blue)

          if let agent = ticket.assignedAgent {
            Text(agent)
              .font(.caption2.monospaced())
              .foregroundStyle(.green)
          }

          if !ticket.tags.isEmpty {
            ForEach(ticket.tags, id: \.self) { tag in
              Text(tag)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.blue.opacity(0.1))
                .clipShape(Capsule())
            }
          }
        }
      }

      Spacer()

      // Status
      statusBadge

      // Time
      VStack(alignment: .trailing, spacing: 1) {
        if let started = ticket.startedAt {
          Text(started, style: .relative)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(ticket.addedAt, style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .frame(width: 70)

      // Actions
      actionButtons
    }
    .padding(.vertical, 4)
    .opacity(ticket.status == .completed || ticket.status == .failed ? 0.6 : 1.0)
  }

  private var priorityBadge: some View {
    Image(systemName: ticket.priority.icon)
      .font(.caption.bold())
      .foregroundStyle(priorityColor)
      .frame(width: 20)
      .help("Priority: \(ticket.priority.label)")
  }

  private var priorityColor: Color {
    switch ticket.priority {
    case .low: return .gray
    case .medium: return .blue
    case .high: return .orange
    case .critical: return .red
    }
  }

  private var statusBadge: some View {
    HStack(spacing: 4) {
      if ticket.status == .running {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 12, height: 12)
      } else {
        Image(systemName: ticket.status.icon)
          .font(.caption2)
      }
      Text(ticket.status.label)
        .font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(statusColor.opacity(0.15))
    .foregroundStyle(statusColor)
    .clipShape(Capsule())
  }

  private var statusColor: Color {
    switch ticket.status {
    case .pending: return .secondary
    case .running: return .green
    case .paused: return .orange
    case .completed: return .green
    case .failed: return .red
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 4) {
      // Priority cycle
      Menu {
        ForEach(QueueTicket.Priority.allCases, id: \.self) { priority in
          Button(priority.label) {
            queueManager.updatePriority(id: ticket.id, priority: priority)
          }
        }
      } label: {
        Image(systemName: "arrow.up.arrow.down")
          .font(.caption)
      }
      .menuStyle(.borderlessButton)
      .frame(width: 24)

      // Pause / Resume
      if ticket.status == .running {
        Button(action: { queueManager.pauseTicket(id: ticket.id) }) {
          Image(systemName: "pause.fill")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Pause agent")
      } else if ticket.status == .paused {
        Button(action: { queueManager.resumeTicket(id: ticket.id) }) {
          Image(systemName: "play.fill")
            .font(.caption)
            .foregroundStyle(.green)
        }
        .buttonStyle(.borderless)
        .help("Resume agent")
      }

      // Remove
      if ticket.status == .pending || ticket.status == .completed || ticket.status == .failed {
        Button(action: { queueManager.removeTicket(id: ticket.id) }) {
          Image(systemName: "xmark")
            .font(.caption)
            .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .help("Remove from queue")
      }
    }
  }
}

// MARK: - Drag & Drop Delegate

struct TicketDropDelegate: DropDelegate {
  let ticket: QueueTicket
  @Binding var draggedTicket: QueueTicket?
  let queueManager: QueueManager

  func performDrop(info: DropInfo) -> Bool {
    draggedTicket = nil
    return true
  }

  func dropEntered(info: DropInfo) {
    guard let dragged = draggedTicket, dragged.id != ticket.id else { return }
    guard let fromIndex = queueManager.tickets.firstIndex(where: { $0.id == dragged.id }),
      let toIndex = queueManager.tickets.firstIndex(where: { $0.id == ticket.id })
    else { return }

    withAnimation(.default) {
      queueManager.moveTicket(
        from: IndexSet(integer: fromIndex),
        to: toIndex > fromIndex ? toIndex + 1 : toIndex
      )
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }
}

// MARK: - Concurrency Gauge

struct ConcurrencyGauge: View {
  let label: String
  let current: Int
  let max: Int
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
        .font(.caption.bold())
        .foregroundStyle(color)
      HStack(spacing: 3) {
        ForEach(0..<max, id: \.self) { i in
          Circle()
            .fill(i < current ? color : color.opacity(0.2))
            .frame(width: 10, height: 10)
        }
      }
      Text("\(current)/\(max)")
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Filter Chip

private struct FilterChip: View {
  let label: String
  let count: Int
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Text(label)
        Text("\(count)")
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(isSelected ? .white.opacity(0.2) : .quaternary)
          .clipShape(Capsule())
      }
      .font(.caption)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(isSelected ? Color.accentColor : Color.clear)
      .foregroundStyle(isSelected ? .white : .primary)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3))
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Add to Queue Sheet

struct AddToQueueSheet: View {
  @EnvironmentObject var agentService: AgentService
  @Environment(\.dismiss) var dismiss

  @State private var ticketID = ""
  @State private var project = ""
  @State private var selectedProvider = ""
  @State private var selectedModel = "Sonnet"
  @State private var selectedPriority: QueueTicket.Priority = .medium
  @State private var tagsText = ""

  private var connectedProviders: [Provider] {
    agentService.providerStore.connectedProviders
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Add Ticket to Queue")
          .font(.headline)
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding()

      Divider()

      Form {
        // Provider
        if !connectedProviders.isEmpty {
          Picker("Provider", selection: $selectedProvider) {
            Text("Select...").tag("")
            ForEach(connectedProviders) { provider in
              Text(provider.name).tag(provider.type.rawValue)
            }
          }
        } else {
          LabeledContent("Provider") {
            Text("No connected providers")
              .foregroundStyle(.secondary)
          }
        }

        // Ticket details
        TextField("Ticket ID", text: $ticketID)
        TextField("Project", text: $project)

        // Model selection
        Picker("Agent Model", selection: $selectedModel) {
          Text("Sonnet").tag("Sonnet")
          Text("Opus").tag("Opus")
        }
        .pickerStyle(.segmented)

        // Priority
        Picker("Priority", selection: $selectedPriority) {
          ForEach(QueueTicket.Priority.allCases, id: \.self) { priority in
            Label(priority.label, systemImage: priority.icon).tag(priority)
          }
        }

        // Tags
        TextField("Tags (comma-separated)", text: $tagsText)
          .help("Used for auto-assignment rules")
      }
      .formStyle(.grouped)

      Divider()

      // Footer
      HStack {
        if agentService.queueManager.isAutoAssignEnabled {
          Label("Auto-assign is on", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Add to Queue") {
          let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
          let ticket = QueueTicket(
            ticketID: ticketID,
            project: project,
            providerType: selectedProvider,
            model: selectedModel,
            priority: selectedPriority,
            tags: tags
          )
          agentService.queueManager.addTicket(ticket)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(ticketID.isEmpty || project.isEmpty || selectedProvider.isEmpty)
        .buttonStyle(.borderedProminent)
      }
      .padding()
    }
    .frame(width: 440, height: 460)
    .onAppear {
      if let first = connectedProviders.first {
        selectedProvider = first.type.rawValue
      }
    }
  }
}

// MARK: - Queue Settings Sheet

struct QueueSettingsSheet: View {
  @EnvironmentObject var agentService: AgentService
  @Environment(\.dismiss) var dismiss

  @State private var newRulePattern = ""
  @State private var newRuleModel = "Sonnet"

  private var queueManager: QueueManager { agentService.queueManager }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Queue Settings")
          .font(.headline)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding()

      Divider()

      Form {
        // Concurrency Limits
        Section("Concurrency Limits") {
          Stepper(
            "Max Sonnet agents: \(queueManager.concurrencyLimits.maxSonnet)",
            value: Binding(
              get: { queueManager.concurrencyLimits.maxSonnet },
              set: { queueManager.concurrencyLimits.maxSonnet = $0 }
            ),
            in: 0...5
          )
          Stepper(
            "Max Opus agents: \(queueManager.concurrencyLimits.maxOpus)",
            value: Binding(
              get: { queueManager.concurrencyLimits.maxOpus },
              set: { queueManager.concurrencyLimits.maxOpus = $0 }
            ),
            in: 0...3
          )
        }

        // Auto-Assignment
        Section("Auto-Assignment Rules") {
          Toggle("Enable auto-assignment", isOn: Binding(
            get: { queueManager.isAutoAssignEnabled },
            set: { queueManager.isAutoAssignEnabled = $0 }
          ))

          if queueManager.isAutoAssignEnabled {
            ForEach(queueManager.autoAssignRules) { rule in
              HStack {
                Image(systemName: "tag")
                  .foregroundStyle(.secondary)
                Text(rule.pattern)
                  .font(.body.monospaced())
                Spacer()
                Image(systemName: "arrow.right")
                  .foregroundStyle(.tertiary)
                Text(rule.assignModel)
                  .font(.caption)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(rule.assignModel == "Opus" ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                  .foregroundStyle(rule.assignModel == "Opus" ? .purple : .blue)
                  .clipShape(Capsule())
                Button(action: { queueManager.removeRule(id: rule.id) }) {
                  Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
              }
            }

            HStack {
              TextField("Pattern (tag/keyword)", text: $newRulePattern)
                .textFieldStyle(.roundedBorder)
              Picker("", selection: $newRuleModel) {
                Text("Sonnet").tag("Sonnet")
                Text("Opus").tag("Opus")
              }
              .frame(width: 100)
              Button("Add") {
                guard !newRulePattern.isEmpty else { return }
                queueManager.addRule(
                  AutoAssignRule(pattern: newRulePattern, assignModel: newRuleModel)
                )
                newRulePattern = ""
              }
              .disabled(newRulePattern.isEmpty)
            }

            Text(
              "Tickets matching a pattern will be automatically assigned to the specified model. Matches against tags, ticket ID, and project name."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
    }
    .frame(width: 500, height: 480)
  }
}
