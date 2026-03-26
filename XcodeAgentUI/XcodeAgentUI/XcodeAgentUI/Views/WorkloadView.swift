import SwiftUI

struct WorkloadView: View {
    @EnvironmentObject var agentService: AgentService
    @StateObject private var balancer = WorkloadBalancer()

    @State private var showAddAgent = false
    @State private var showAddTicket = false
    @State private var showScheduleSheet = false
    @State private var selectedAgentForSchedule: AgentWorker?
    @State private var draggedTicket: WorkloadTicket?
    @State private var dragSourceAgentID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HSplitView {
                agentGrid
                    .frame(minWidth: 500)
                unassignedPanel
                    .frame(minWidth: 220, maxWidth: 300)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Workload Balancer")
                .font(.title2.bold())

            Spacer()

            statsBar

            Divider().frame(height: 20)

            Picker("Strategy", selection: $balancer.balancingStrategy) {
                ForEach(BalancingStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.rawValue).tag(strategy)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .help(balancer.balancingStrategy.description)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    balancer.rebalanceAll()
                }
            } label: {
                Label("Re-balance", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .help("Redistribute all tickets across available agents")

            Button {
                showAddAgent = true
            } label: {
                Label("Add Agent", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .sheet(isPresented: $showAddAgent) {
            AddAgentSheet(balancer: balancer)
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatBadge(
                label: "Agents",
                value: "\(balancer.agents.count)",
                icon: "cpu",
                color: .purple
            )
            StatBadge(
                label: "Active",
                value: "\(balancer.activeAgentCount)",
                icon: "bolt.fill",
                color: .green
            )
            StatBadge(
                label: "Tickets",
                value: "\(balancer.totalTickets)",
                icon: "ticket",
                color: .blue
            )
            StatBadge(
                label: "Avg Load",
                value: "\(Int(balancer.averageLoad * 100))%",
                icon: "gauge.medium",
                color: loadColor(balancer.averageLoad)
            )
        }
    }

    // MARK: - Agent Grid

    private var agentGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(balancer.agents) { agent in
                    AgentCoreCard(
                        agent: agent,
                        balancer: balancer,
                        draggedTicket: $draggedTicket,
                        dragSourceAgentID: $dragSourceAgentID,
                        onSchedule: {
                            selectedAgentForSchedule = agent
                            showScheduleSheet = true
                        }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3))
        .sheet(isPresented: $showScheduleSheet) {
            if let agent = selectedAgentForSchedule {
                ScheduleAgentSheet(agent: agent, balancer: balancer)
            }
        }
    }

    // MARK: - Unassigned Panel

    private var unassignedPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tray.full")
                    .foregroundColor(.orange)
                Text("Unassigned")
                    .font(.headline)
                Spacer()
                Text("\(balancer.unassignedTickets.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(balancer.unassignedTickets.isEmpty ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if balancer.unassignedTickets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.green.opacity(0.5))
                    Text("All tickets assigned")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(balancer.unassignedTickets.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder })) { ticket in
                            TicketCard(ticket: ticket, compact: true)
                                .onDrag {
                                    draggedTicket = ticket
                                    dragSourceAgentID = nil
                                    return NSItemProvider(object: ticket.id.uuidString as NSString)
                                }
                                .contextMenu {
                                    Button("Auto-assign") {
                                        withAnimation {
                                            balancer.autoAssignSingle(ticket)
                                        }
                                    }
                                    Divider()
                                    Menu("Assign to...") {
                                        ForEach(balancer.agents.filter { $0.isAvailable }) { agent in
                                            Button(agent.name) {
                                                withAnimation {
                                                    balancer.assignTicket(ticket, to: agent)
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) {
                                        withAnimation {
                                            balancer.removeTicket(ticket)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    showAddTicket = true
                } label: {
                    Label("Add Ticket", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !balancer.unassignedTickets.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            balancer.autoBalance()
                        }
                    } label: {
                        Label("Auto", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Auto-assign all unassigned tickets")
                }
            }
            .padding(8)
            .background(.bar)
        }
        .sheet(isPresented: $showAddTicket) {
            AddTicketSheet(balancer: balancer)
        }
    }

    // MARK: - Helpers

    private func loadColor(_ load: Double) -> Color {
        if load < 0.4 { return .green }
        if load < 0.7 { return .yellow }
        return .red
    }
}

// MARK: - Agent Core Card

struct AgentCoreCard: View {
    @ObservedObject var agent: AgentWorker
    @ObservedObject var balancer: WorkloadBalancer
    @Binding var draggedTicket: WorkloadTicket?
    @Binding var dragSourceAgentID: UUID?
    var onSchedule: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                // CPU core indicator
                ZStack {
                    Circle()
                        .fill(stateColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(stateColor, lineWidth: 2)
                        .frame(width: 36, height: 36)
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(stateColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(agent.name)
                            .font(.headline)
                        Text("(\(agent.model == .opus ? "Opus" : "Sonnet"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(agent.state.label)
                        .font(.caption)
                        .foregroundColor(stateColor)
                }

                Spacer()

                // Load gauge
                loadGauge

                // Actions menu
                Menu {
                    Button(agent.state == .paused ? "Resume" : "Pause") {
                        withAnimation { balancer.toggleAgentState(agent) }
                    }
                    Button("Schedule...") { onSchedule() }
                    if agent.state != .offline {
                        Button("Set Offline") {
                            withAnimation { balancer.setAgentOffline(agent) }
                        }
                    }
                    Divider()
                    Button("Remove Agent", role: .destructive) {
                        withAnimation { balancer.removeAgent(agent) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(stateColor.opacity(0.05))

            Divider()

            // Schedule indicator
            if let schedule = agent.schedule {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text(schedule.label.isEmpty ? schedule.recurrence.rawValue : schedule.label)
                        .font(.caption2)
                    Spacer()
                    Text(schedule.durationFormatted)
                        .font(.caption2.bold())
                        .foregroundColor(.purple)
                    Button {
                        withAnimation { balancer.clearSchedule(agent) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.05))
                Divider()
            }

            // Ticket list
            if agent.assignedTickets.isEmpty {
                VStack(spacing: 4) {
                    Text("No tickets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Drop tickets here")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(8)
            } else {
                VStack(spacing: 6) {
                    ForEach(agent.assignedTickets) { ticket in
                        TicketCard(ticket: ticket, compact: false)
                            .onDrag {
                                draggedTicket = ticket
                                dragSourceAgentID = agent.id
                                return NSItemProvider(object: ticket.id.uuidString as NSString)
                            }
                            .contextMenu {
                                Menu("Move to...") {
                                    ForEach(balancer.agents.filter { $0.id != agent.id && $0.isAvailable }) { other in
                                        Button(other.name) {
                                            withAnimation {
                                                balancer.moveTicket(ticket, from: agent, to: other)
                                            }
                                        }
                                    }
                                }
                                Button("Unassign") {
                                    withAnimation {
                                        balancer.unassignTicket(ticket, from: agent)
                                    }
                                }
                                Divider()
                                Button("Remove", role: .destructive) {
                                    withAnimation { balancer.removeTicket(ticket) }
                                }
                            }
                    }
                }
                .padding(8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .onDrop(of: [.text], isTargeted: $isDropTargeted) { providers in
            handleDrop()
            return true
        }
    }

    private func handleDrop() {
        guard let ticket = draggedTicket else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            if let sourceID = dragSourceAgentID,
               let source = balancer.agents.first(where: { $0.id == sourceID }) {
                balancer.moveTicket(ticket, from: source, to: agent)
            } else {
                balancer.assignTicket(ticket, to: agent)
            }
        }

        draggedTicket = nil
        dragSourceAgentID = nil
    }

    private var stateColor: Color {
        switch agent.state {
        case .idle: return .green
        case .working: return .blue
        case .paused: return .yellow
        case .offline: return .gray
        case .scheduled: return .purple
        }
    }

    private var loadGauge: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: agent.cpuLoad)
                    .stroke(loadColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                Text("\(agent.ticketCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
        }
    }

    private var loadColor: Color {
        if agent.cpuLoad < 0.4 { return .green }
        if agent.cpuLoad < 0.7 { return .yellow }
        return .red
    }
}

// MARK: - Ticket Card

struct TicketCard: View {
    let ticket: WorkloadTicket
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ticket.ticketID)
                        .font(.system(.caption, design: .monospaced).bold())
                    if !compact {
                        Text(ticket.project)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(ticket.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !compact, let est = ticket.estimatedMinutes {
                Text("\(est)m")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            Text(ticket.priority.label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(priorityColor.opacity(0.15))
                .foregroundColor(priorityColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        )
    }

    private var priorityColor: Color {
        switch ticket.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Agent Sheet

struct AddAgentSheet: View {
    @ObservedObject var balancer: WorkloadBalancer
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var model: AgentModel = .sonnet

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Agent")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Agent Configuration") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Model", selection: $model) {
                        ForEach(AgentModel.allCases, id: \.self) { m in
                            Text(m == .opus ? "Opus — Complex features" : "Sonnet — Quick fixes")
                                .tag(m)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Add Agent") {
                    balancer.addAgent(name: name.isEmpty ? "Agent-\(balancer.agents.count + 1)" : name, model: model)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 380)
    }
}

// MARK: - Add Ticket Sheet

struct AddTicketSheet: View {
    @ObservedObject var balancer: WorkloadBalancer
    @Environment(\.dismiss) var dismiss

    @State private var ticketID = ""
    @State private var title = ""
    @State private var project = ""
    @State private var provider = "github"
    @State private var priority: TicketPriority = .medium
    @State private var estimatedMinutes = ""
    @State private var autoAssign = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Ticket")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Ticket Details") {
                    HStack {
                        TextField("Ticket ID", text: $ticketID)
                            .textFieldStyle(.roundedBorder)
                        TextField("Project", text: $project)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Title / Description", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Configuration") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TicketPriority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Estimated minutes (optional)", text: $estimatedMinutes)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Auto-assign to best agent", isOn: $autoAssign)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Add Ticket") {
                    let ticket = WorkloadTicket(
                        ticketID: ticketID,
                        title: title.isEmpty ? ticketID : title,
                        project: project,
                        provider: provider,
                        priority: priority,
                        estimatedMinutes: Int(estimatedMinutes)
                    )
                    if autoAssign {
                        balancer.addTicket(ticket)
                        balancer.autoAssignSingle(ticket)
                    } else {
                        balancer.addTicket(ticket)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ticketID.isEmpty || project.isEmpty)
            }
            .padding()
        }
        .frame(width: 420)
    }
}

// MARK: - Schedule Agent Sheet

struct ScheduleAgentSheet: View {
    @ObservedObject var agent: AgentWorker
    @ObservedObject var balancer: WorkloadBalancer
    @Environment(\.dismiss) var dismiss

    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var recurrence: ScheduleRecurrence = .once
    @State private var label = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Schedule \(agent.name)")
                    .font(.title3.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Time Window") {
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime)
                }

                Section("Recurrence") {
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(ScheduleRecurrence.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Label") {
                    TextField("e.g. Night shift, Sprint review", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()

            Divider()

            HStack {
                if agent.schedule != nil {
                    Button("Clear Schedule", role: .destructive) {
                        balancer.clearSchedule(agent)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Set Schedule") {
                    let schedule = AgentSchedule(
                        startTime: startTime,
                        endTime: endTime,
                        recurrence: recurrence,
                        label: label
                    )
                    balancer.scheduleAgent(agent, schedule: schedule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(endTime <= startTime)
            }
            .padding()
        }
        .frame(width: 400)
    }
}
