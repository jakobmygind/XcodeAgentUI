import Foundation

// MARK: - Stored Metric Records

/// A single completed ticket run tracked for performance analytics
struct TicketRun: Identifiable, Codable {
  let id: String              // UUID
  let ticketID: String
  let project: String
  let agentModel: String      // "sonnet" or "opus"
  let startedAt: Date
  let finishedAt: Date
  let outcome: RunOutcome
  let buildSucceeded: Bool
  let testsSucceeded: Bool
  let retryCount: Int
  let inputTokens: Int
  let outputTokens: Int

  var durationSeconds: TimeInterval {
    finishedAt.timeIntervalSince(startedAt)
  }

  var estimatedCost: Double {
    // Pricing per 1M tokens (rough estimates)
    let inputRate: Double
    let outputRate: Double
    switch agentModel {
    case "opus":
      inputRate = 15.0 / 1_000_000
      outputRate = 75.0 / 1_000_000
    default: // sonnet
      inputRate = 3.0 / 1_000_000
      outputRate = 15.0 / 1_000_000
    }
    return Double(inputTokens) * inputRate + Double(outputTokens) * outputRate
  }
}

enum RunOutcome: String, Codable, CaseIterable {
  case success
  case failure
  case timeout
  case aborted
}

// MARK: - Aggregated Stats

struct AgentStats: Identifiable {
  let model: String
  var id: String { model }
  var totalRuns: Int = 0
  var successes: Int = 0
  var failures: Int = 0
  var totalDuration: TimeInterval = 0
  var totalRetries: Int = 0
  var buildSuccesses: Int = 0
  var testSuccesses: Int = 0
  var totalInputTokens: Int = 0
  var totalOutputTokens: Int = 0
  var totalCost: Double = 0

  var successRate: Double {
    totalRuns > 0 ? Double(successes) / Double(totalRuns) : 0
  }
  var avgDuration: TimeInterval {
    totalRuns > 0 ? totalDuration / Double(totalRuns) : 0
  }
  var buildSuccessRate: Double {
    totalRuns > 0 ? Double(buildSuccesses) / Double(totalRuns) : 0
  }
  var testPassRate: Double {
    totalRuns > 0 ? Double(testSuccesses) / Double(totalRuns) : 0
  }
  var avgRetries: Double {
    totalRuns > 0 ? Double(totalRetries) / Double(totalRuns) : 0
  }
  var avgCost: Double {
    totalRuns > 0 ? totalCost / Double(totalRuns) : 0
  }
}

/// Daily aggregation for trend charts
struct DailyMetric: Identifiable {
  let date: Date
  let model: String
  var id: String { "\(date.timeIntervalSince1970)-\(model)" }
  var runs: Int = 0
  var successes: Int = 0
  var avgDuration: TimeInterval = 0
  var totalCost: Double = 0
}

// MARK: - Time Range Filter

enum MetricsTimeRange: String, CaseIterable, Identifiable {
  case day = "24h"
  case week = "7d"
  case month = "30d"
  case all = "All"

  var id: String { rawValue }

  var startDate: Date? {
    switch self {
    case .day: return Calendar.current.date(byAdding: .day, value: -1, to: Date())
    case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
    case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
    case .all: return nil
    }
  }
}
