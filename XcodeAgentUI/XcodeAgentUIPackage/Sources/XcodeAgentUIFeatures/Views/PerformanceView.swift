import Charts
import SwiftUI
import XcodeAgentUICore

public struct PerformanceView: View {
  @Environment(AgentService.self) var agentService
  @Bindable var metricsStore: MetricsStore

  public init(metricsStore: MetricsStore) {
    self.metricsStore = metricsStore
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        headerBar
        summaryCards
        chartsSection
        recentRunsTable
      }
      .padding()
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: - Header

  private var headerBar: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Agent Performance")
          .font(.title2.bold())
        Text("\(metricsStore.runs.count) runs tracked")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Picker("Range", selection: $metricsStore.timeRange) {
        ForEach(MetricsTimeRange.allCases) { range in
          Text(range.rawValue).tag(range)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 220)

      Menu {
        Button("Import Logs...") { importLogs() }
        Button("Generate Demo Data") { metricsStore.seedDemoData() }
        Divider()
        Button("Clear All Data", role: .destructive) { metricsStore.clearAll() }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
    }
  }

  // MARK: - Summary Cards

  private var summaryCards: some View {
    let allStats = metricsStore.agentStats
    let totalRuns = allStats.map(\.totalRuns).reduce(0, +)
    let totalSuccesses = allStats.map(\.successes).reduce(0, +)
    let totalCost = allStats.map(\.totalCost).reduce(0, +)
    let avgDuration: TimeInterval = totalRuns > 0
      ? allStats.map(\.totalDuration).reduce(0, +) / Double(totalRuns) : 0

    return HStack(spacing: 12) {
      SummaryCard(
        title: "Total Runs",
        value: "\(totalRuns)",
        detail: "\(totalSuccesses) succeeded",
        color: .blue
      )
      SummaryCard(
        title: "Success Rate",
        value: totalRuns > 0
          ? String(format: "%.0f%%", Double(totalSuccesses) / Double(totalRuns) * 100) : "--",
        detail: "\(totalRuns - totalSuccesses) failed",
        color: totalRuns > 0 && Double(totalSuccesses) / Double(totalRuns) > 0.7 ? .green : .orange
      )
      SummaryCard(
        title: "Avg Duration",
        value: formatDuration(avgDuration),
        detail: "per ticket",
        color: .purple
      )
      SummaryCard(
        title: "Total Cost",
        value: String(format: "$%.2f", totalCost),
        detail: totalRuns > 0
          ? String(format: "$%.2f avg", totalCost / Double(totalRuns)) : "--",
        color: .orange
      )
    }
  }

  // MARK: - Charts

  private var chartsSection: some View {
    VStack(spacing: 16) {
      HStack(alignment: .top, spacing: 16) {
        successRateByModel
        buildTestRates
      }

      HStack(alignment: .top, spacing: 16) {
        dailyRunsChart
        costChart
      }

      HStack(alignment: .top, spacing: 16) {
        durationChart
        retryChart
      }
    }
  }

  private var successRateByModel: some View {
    ChartCard(title: "Success Rate by Model") {
      if metricsStore.agentStats.isEmpty {
        emptyChartPlaceholder
      } else {
        Chart(metricsStore.agentStats) { stat in
          BarMark(
            x: .value("Model", stat.model.capitalized),
            y: .value("Rate", stat.successRate * 100)
          )
          .foregroundStyle(stat.model == "opus" ? Color.blue : Color.cyan)
          .annotation(position: .top) {
            Text(String(format: "%.0f%%", stat.successRate * 100))
              .font(.caption2)
          }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
          AxisMarks(values: [0, 25, 50, 75, 100]) { value in
            AxisGridLine()
            AxisValueLabel {
              Text("\(value.as(Int.self) ?? 0)%")
            }
          }
        }
        .frame(height: 180)
      }
    }
  }

  private var buildTestRates: some View {
    ChartCard(title: "Build & Test Pass Rates") {
      if metricsStore.agentStats.isEmpty {
        emptyChartPlaceholder
      } else {
        let data = metricsStore.agentStats.flatMap { stat -> [(String, String, Double)] in
          [
            (stat.model.capitalized, "Build", stat.buildSuccessRate * 100),
            (stat.model.capitalized, "Tests", stat.testPassRate * 100),
          ]
        }
        Chart(data, id: \.0) { item in
          BarMark(
            x: .value("Model", item.0),
            y: .value("Rate", item.2)
          )
          .foregroundStyle(by: .value("Type", item.1))
          .position(by: .value("Type", item.1))
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale(["Build": .green, "Tests": .teal])
        .frame(height: 180)
      }
    }
  }

  private var dailyRunsChart: some View {
    ChartCard(title: "Daily Runs") {
      if metricsStore.dailyMetrics.isEmpty {
        emptyChartPlaceholder
      } else {
        Chart(metricsStore.dailyMetrics) { metric in
          BarMark(
            x: .value("Date", metric.date, unit: .day),
            y: .value("Runs", metric.runs)
          )
          .foregroundStyle(by: .value("Model", metric.model.capitalized))
        }
        .chartForegroundStyleScale(["Opus": Color.blue, "Sonnet": Color.cyan])
        .frame(height: 180)
      }
    }
  }

  private var costChart: some View {
    ChartCard(title: "Daily Cost") {
      if metricsStore.dailyMetrics.isEmpty {
        emptyChartPlaceholder
      } else {
        Chart(metricsStore.dailyMetrics) { metric in
          LineMark(
            x: .value("Date", metric.date, unit: .day),
            y: .value("Cost", metric.totalCost)
          )
          .foregroundStyle(by: .value("Model", metric.model.capitalized))
          AreaMark(
            x: .value("Date", metric.date, unit: .day),
            y: .value("Cost", metric.totalCost)
          )
          .foregroundStyle(by: .value("Model", metric.model.capitalized))
          .opacity(0.1)
        }
        .chartForegroundStyleScale(["Opus": Color.blue, "Sonnet": Color.cyan])
        .chartYAxis {
          AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
              Text("$\(value.as(Double.self) ?? 0, specifier: "%.2f")")
            }
          }
        }
        .frame(height: 180)
      }
    }
  }

  private var durationChart: some View {
    ChartCard(title: "Avg Duration (min)") {
      if metricsStore.dailyMetrics.isEmpty {
        emptyChartPlaceholder
      } else {
        Chart(metricsStore.dailyMetrics) { metric in
          PointMark(
            x: .value("Date", metric.date, unit: .day),
            y: .value("Minutes", metric.avgDuration / 60)
          )
          .foregroundStyle(by: .value("Model", metric.model.capitalized))
          .symbolSize(60)
          LineMark(
            x: .value("Date", metric.date, unit: .day),
            y: .value("Minutes", metric.avgDuration / 60)
          )
          .foregroundStyle(by: .value("Model", metric.model.capitalized))
          .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartForegroundStyleScale(["Opus": Color.blue, "Sonnet": Color.cyan])
        .frame(height: 180)
      }
    }
  }

  private var retryChart: some View {
    ChartCard(title: "Self-Healing Retries") {
      if metricsStore.agentStats.isEmpty {
        emptyChartPlaceholder
      } else {
        Chart(metricsStore.agentStats) { stat in
          BarMark(
            x: .value("Model", stat.model.capitalized),
            y: .value("Avg Retries", stat.avgRetries)
          )
          .foregroundStyle(stat.model == "opus" ? Color.blue : Color.cyan)
          .annotation(position: .top) {
            Text(String(format: "%.1f", stat.avgRetries))
              .font(.caption2)
          }
        }
        .frame(height: 180)
      }
    }
  }

  private var emptyChartPlaceholder: some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.bar.xaxis")
        .font(.title)
        .foregroundColor(.secondary)
      Text("No data yet")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(height: 180)
    .frame(maxWidth: .infinity)
  }

  // MARK: - Recent Runs Table

  private var recentRunsTable: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent Runs")
        .font(.headline)

      if metricsStore.runs.isEmpty {
        HStack {
          Spacer()
          VStack(spacing: 8) {
            Image(systemName: "tray")
              .font(.largeTitle)
              .foregroundColor(.secondary)
            Text("No runs recorded")
              .foregroundColor(.secondary)
            Button("Generate Demo Data") {
              metricsStore.seedDemoData()
            }
            .buttonStyle(.bordered)
          }
          .padding(40)
          Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
      } else {
        VStack(spacing: 0) {
          // Header row
          HStack(spacing: 0) {
            tableHeader("Ticket", width: 100)
            tableHeader("Project", width: 90)
            tableHeader("Model", width: 70)
            tableHeader("Outcome", width: 80)
            tableHeader("Build", width: 55)
            tableHeader("Tests", width: 55)
            tableHeader("Retries", width: 60)
            tableHeader("Duration", width: 80)
            tableHeader("Cost", width: 70)
            tableHeader("Date", width: 100)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .background(Color(nsColor: .controlBackgroundColor))

          Divider()

          // Data rows
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(metricsStore.runs.prefix(50)) { run in
                RunRow(run: run)
                Divider()
              }
            }
          }
          .frame(maxHeight: 300)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
      }
    }
  }

  private func tableHeader(_ title: String, width: CGFloat) -> some View {
    Text(title)
      .font(.caption.bold())
      .foregroundColor(.secondary)
      .frame(width: width, alignment: .leading)
  }

  // MARK: - Actions

  private func importLogs() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message = "Select agent logs directory"
    panel.prompt = "Import"
    if panel.runModal() == .OK, let url = panel.url {
      let runs = LogParser.scanLogDirectory(at: url.path)
      for run in runs {
        metricsStore.record(run)
      }
    }
  }

  // MARK: - Formatting

  private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return String(format: "%.0fs", seconds) }
    let min = Int(seconds) / 60
    let sec = Int(seconds) % 60
    return "\(min)m \(sec)s"
  }
}

// MARK: - Sub-Components

struct SummaryCard: View {
  let title: String
  let value: String
  let detail: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
      Text(value)
        .font(.title2.bold().monospacedDigit())
        .foregroundColor(color)
      Text(detail)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(color.opacity(0.08))
    .cornerRadius(10)
  }
}

struct ChartCard<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.subheadline.bold())
      content()
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(10)
  }
}

struct RunRow: View {
  let run: TicketRun

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm"
    return f
  }()

  var body: some View {
    HStack(spacing: 0) {
      Text(run.ticketID)
        .font(.caption.monospaced())
        .frame(width: 100, alignment: .leading)

      Text(run.project)
        .font(.caption)
        .frame(width: 90, alignment: .leading)
        .lineLimit(1)

      modelBadge
        .frame(width: 70, alignment: .leading)

      outcomeBadge
        .frame(width: 80, alignment: .leading)

      statusIcon(run.buildSucceeded)
        .frame(width: 55, alignment: .leading)

      statusIcon(run.testsSucceeded)
        .frame(width: 55, alignment: .leading)

      Text("\(run.retryCount)")
        .font(.caption.monospacedDigit())
        .foregroundColor(run.retryCount > 2 ? .orange : .primary)
        .frame(width: 60, alignment: .leading)

      Text(formatDuration(run.durationSeconds))
        .font(.caption.monospacedDigit())
        .frame(width: 80, alignment: .leading)

      Text(String(format: "$%.2f", run.estimatedCost))
        .font(.caption.monospacedDigit())
        .frame(width: 70, alignment: .leading)

      Text(Self.dateFormatter.string(from: run.startedAt))
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 100, alignment: .leading)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  private var modelBadge: some View {
    Text(run.agentModel.capitalized)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(run.agentModel == "opus" ? Color.blue.opacity(0.15) : Color.cyan.opacity(0.15))
      .foregroundColor(run.agentModel == "opus" ? .blue : .cyan)
      .cornerRadius(4)
  }

  private var outcomeBadge: some View {
    let (label, color): (String, Color) = {
      switch run.outcome {
      case .success: return ("Success", .green)
      case .failure: return ("Failed", .red)
      case .timeout: return ("Timeout", .orange)
      case .aborted: return ("Aborted", .gray)
      }
    }()
    return Text(label)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15))
      .foregroundColor(color)
      .cornerRadius(4)
  }

  private func statusIcon(_ passed: Bool) -> some View {
    Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
      .font(.caption)
      .foregroundColor(passed ? .green : .red.opacity(0.6))
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let min = Int(seconds) / 60
    let sec = Int(seconds) % 60
    return "\(min)m \(sec)s"
  }
}

// MARK: - Preview

#Preview {
  let store = MetricsStore()
  PerformanceView(metricsStore: store)
    .environment(MockAgentService() as AgentService)
    .frame(width: 1000, height: 800)
}
