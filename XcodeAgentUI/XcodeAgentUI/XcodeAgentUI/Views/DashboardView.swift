import SwiftUI

struct DashboardView: View {
  @EnvironmentObject var agentService: AgentService

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        // Header
        HStack {
          Text("System Dashboard")
            .font(.largeTitle)
            .fontWeight(.bold)
          Spacer()
          Button("Start All") { agentService.startAll() }
            .buttonStyle(.borderedProminent)
            .disabled(agentService.routerRunner.isRunning && agentService.bridgeRunner.isRunning)
          Button("Stop All") { agentService.stopAll() }
            .buttonStyle(.bordered)
            .disabled(!agentService.routerRunner.isRunning && !agentService.bridgeRunner.isRunning)
        }

        // Service Cards
        HStack(spacing: 16) {
          ServiceCard(
            status: agentService.routerStatus,
            logs: agentService.routerRunner.output,
            onStart: { agentService.startRouter() },
            onStop: { agentService.stopRouter() }
          )
          ServiceCard(
            status: agentService.bridgeStatus,
            logs: agentService.bridgeRunner.output,
            onStart: { agentService.startBridge() },
            onStop: { agentService.stopBridge() }
          )
        }

        // Bridge Connections
        GroupBox("Bridge Connections") {
          if agentService.bridgeWS.isConnected {
            if agentService.bridgeWS.connectedClients.isEmpty {
              Text("Connected — no other clients")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
              VStack(alignment: .leading, spacing: 4) {
                ForEach(agentService.bridgeWS.connectedClients) { client in
                  HStack {
                    Image(systemName: iconForRole(client.role))
                      .foregroundStyle(colorForRole(client.role))
                    Text(client.name)
                      .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(client.role)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .padding(.vertical, 4)
            }
          } else {
            HStack {
              Image(systemName: "wifi.slash")
                .foregroundStyle(.red)
              Text("Not connected to bridge")
                .foregroundStyle(.secondary)
              Spacer()
              Button("Connect") {
                agentService.bridgeWS.connect()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(.vertical, 4)
          }
        }

        // Combined Log View
        GroupBox("Recent Logs") {
          LogOutputView(
            lines: combinedLogs(),
            maxHeight: 250
          )
        }
      }
      .padding()
    }
  }

  private func combinedLogs() -> [String] {
    let routerLines = agentService.routerRunner.output.suffix(50).map { "[Router] \($0)" }
    let bridgeLines = agentService.bridgeRunner.output.suffix(50).map { "[Bridge] \($0)" }
    return Array(routerLines) + Array(bridgeLines)
  }

  private func iconForRole(_ role: String) -> String {
    switch role {
    case "agent": return "cpu"
    case "human": return "person.fill"
    case "observer": return "eye"
    default: return "questionmark.circle"
    }
  }

  private func colorForRole(_ role: String) -> Color {
    switch role {
    case "agent": return .purple
    case "human": return .blue
    case "observer": return .green
    default: return .gray
    }
  }
}

struct ServiceCard: View {
  let status: ServiceStatus
  let logs: [String]
  let onStart: () -> Void
  let onStop: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Circle()
            .fill(stateColor)
            .frame(width: 10, height: 10)
          Text(status.name)
            .font(.headline)
          Spacer()
          if let port = status.port {
            Text(":\(port)")
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }

        Text(status.state.rawValue)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        HStack {
          Button("Start") { onStart() }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(status.state == .running || status.state == .starting)

          Button("Stop") { onStop() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(status.state == .stopped)
        }

        if !logs.isEmpty {
          Divider()
          LogOutputView(lines: Array(logs.suffix(10)), maxHeight: 80)
        }
      }
      .padding(.vertical, 4)
    }
  }

  private var stateColor: Color {
    switch status.state {
    case .stopped: return .gray
    case .starting: return .yellow
    case .running: return .green
    case .error: return .red
    }
  }
}

struct LogOutputView: View {
  let lines: [String]
  var maxHeight: CGFloat = 200

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 1) {
          ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            Text(line)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(lineColor(line))
              .textSelection(.enabled)
              .id(index)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
      }
      .frame(maxHeight: maxHeight)
      .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .onChange(of: lines.count) { _ in
        if let last = lines.indices.last {
          proxy.scrollTo(last, anchor: .bottom)
        }
      }
    }
  }

  private func lineColor(_ line: String) -> Color {
    if line.contains("[Error]") || line.contains("error") || line.contains("ERR") {
      return .red
    }
    if line.contains("[Warning]") || line.contains("warning") || line.contains("WARN") {
      return .yellow
    }
    return .primary
  }
}
