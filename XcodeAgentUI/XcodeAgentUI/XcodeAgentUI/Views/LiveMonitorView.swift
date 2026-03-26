import SwiftUI

struct LiveMonitorView: View {
  @EnvironmentObject var agentService: AgentService
  @State private var commandText = ""
  @State private var filterType: String? = nil
  @State private var screenshotImage: NSImage?

  private var ws: BridgeWebSocket { agentService.bridgeWS }

  var body: some View {
    VStack(spacing: 0) {
      // Header Bar
      HStack {
        Text("Live Monitor")
          .font(.largeTitle)
          .fontWeight(.bold)

        Spacer()

        // Connection status
        HStack(spacing: 6) {
          Circle()
            .fill(ws.isConnected ? Color.green : Color.red)
            .frame(width: 8, height: 8)
          Text(ws.isConnected ? "Connected" : "Disconnected")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if !ws.isConnected {
          Button("Connect") { ws.connect() }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
          Button("Disconnect") { ws.disconnect() }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
      .padding()

      // Filter Bar
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          FilterChip(label: "All", isSelected: filterType == nil) {
            filterType = nil
          }
          FilterChip(label: "Output", isSelected: filterType == "agent_output") {
            filterType = "agent_output"
          }
          FilterChip(label: "Status", isSelected: filterType == "agent_status") {
            filterType = "agent_status"
          }
          FilterChip(label: "Files", isSelected: filterType == "file_changed") {
            filterType = "file_changed"
          }
          FilterChip(label: "Errors", isSelected: filterType == "agent_error") {
            filterType = "agent_error"
          }
          FilterChip(label: "System", isSelected: filterType == "system") {
            filterType = "system"
          }

          Spacer()

          Button(action: { ws.messages.removeAll() }) {
            Image(systemName: "trash")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("Clear messages")

          Text("\(filteredMessages.count) messages")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
      }
      .padding(.bottom, 8)

      Divider()

      // Message Stream
      HSplitView {
        // Main message list
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
              ForEach(filteredMessages) { msg in
                MessageRow(envelope: msg)
                  .id(msg.id)
              }
            }
            .padding(8)
          }
          .onChange(of: filteredMessages.count) { _ in
            if let last = filteredMessages.last {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }

        // Screenshot panel (if available)
        if let image = screenshotImage {
          VStack {
            Text("Screenshot")
              .font(.caption)
              .foregroundStyle(.secondary)
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .shadow(radius: 2)
          }
          .frame(minWidth: 200, maxWidth: 300)
          .padding()
        }
      }

      Divider()

      // Command Input
      HStack(spacing: 8) {
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
        TextField("Send command to agent...", text: $commandText)
          .textFieldStyle(.roundedBorder)
          .onSubmit { sendCommand() }
          .disabled(!ws.isConnected)

        Button("Send") { sendCommand() }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(!ws.isConnected || commandText.isEmpty)
      }
      .padding()
    }
  }

  private var filteredMessages: [BridgeEnvelope] {
    guard let filter = filterType else { return ws.messages }
    return ws.messages.filter { $0.type == filter }
  }

  private func sendCommand() {
    guard !commandText.isEmpty else { return }
    ws.send(type: "human_command", payload: commandText)
    commandText = ""
  }
}

struct MessageRow: View {
  let envelope: BridgeEnvelope

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(formattedTime)
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 55, alignment: .trailing)

      Image(systemName: typeIcon)
        .font(.system(size: 10))
        .foregroundStyle(typeColor)
        .frame(width: 14)

      Text(envelope.payload.stringValue)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(typeColor)
        .textSelection(.enabled)
        .lineLimit(5)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 1)
  }

  private var formattedTime: String {
    // Parse ISO 8601 and show HH:mm:ss
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: envelope.ts) {
      let display = DateFormatter()
      display.dateFormat = "HH:mm:ss"
      return display.string(from: date)
    }
    return envelope.ts.suffix(8).description
  }

  private var typeIcon: String {
    switch envelope.type {
    case "agent_output": return "text.alignleft"
    case "agent_status": return "heart.fill"
    case "agent_error": return "exclamationmark.triangle.fill"
    case "file_changed": return "doc.badge.arrow.up"
    case "system": return "gear"
    case "human_command": return "person.fill"
    case "agent_approval_request": return "questionmark.circle.fill"
    default: return "circle"
    }
  }

  private var typeColor: Color {
    switch envelope.type {
    case "agent_error": return .red
    case "agent_approval_request": return .orange
    case "system": return .blue
    case "file_changed": return .cyan
    case "agent_status": return .green
    case "human_command": return .purple
    default: return .primary
    }
  }
}

struct FilterChip: View {
  let label: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}
