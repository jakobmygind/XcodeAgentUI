import Foundation

// MARK: - Stored Metric Records

/// A single completed ticket run tracked for performance analytics
public struct TicketRun: Identifiable, Codable, Sendable {
  public let id: String              // UUID
  public let ticketID: String
  public let project: String
  public let agentModel: String      // "sonnet" or "opus"
  public let startedAt: Date
  public let finishedAt: Date
  public let outcome: RunOutcome
  public let buildSucceeded: Bool
  public let testsSucceeded: Bool
  public let retryCount: Int
  public let inputTokens: Int
  public let outputTokens: Int

  public var durationSeconds: TimeInterval {
    finishedAt.timeIntervalSince(startedAt)
  }

  public var estimatedCost: Double {
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

public enum RunOutcome: String, Codable, CaseIterable, Sendable {
  case success
  case failure
  case timeout
  case aborted
}

// MARK: - Aggregated Stats

public struct AgentStats: Identifiable {
  public let model: String
  public var id: String { model }
  public var totalRuns: Int = 0
  public var successes: Int = 0
  public var failures: Int = 0
  public var totalDuration: TimeInterval = 0
  public var totalRetries: Int = 0
  public var buildSuccesses: Int = 0
  public var testSuccesses: Int = 0
  public var totalInputTokens: Int = 0
  public var totalOutputTokens: Int = 0
  public var totalCost: Double = 0

  public init(model: String) {
    self.model = model
  }

  public var successRate: Double {
    totalRuns > 0 ? Double(successes) / Double(totalRuns) : 0
  }
  public var avgDuration: TimeInterval {
    totalRuns > 0 ? totalDuration / Double(totalRuns) : 0
  }
  public var buildSuccessRate: Double {
    totalRuns > 0 ? Double(buildSuccesses) / Double(totalRuns) : 0
  }
  public var testPassRate: Double {
    totalRuns > 0 ? Double(testSuccesses) / Double(totalRuns) : 0
  }
  public var avgRetries: Double {
    totalRuns > 0 ? Double(totalRetries) / Double(totalRuns) : 0
  }
  public var avgCost: Double {
    totalRuns > 0 ? totalCost / Double(totalRuns) : 0
  }
}

/// Daily aggregation for trend charts
public struct DailyMetric: Identifiable {
  public let date: Date
  public let model: String
  public var id: String { "\(date.timeIntervalSince1970)-\(model)" }
  public var runs: Int = 0
  public var successes: Int = 0
  public var avgDuration: TimeInterval = 0
  public var totalCost: Double = 0

  public init(date: Date, model: String) {
    self.date = date
    self.model = model
  }
}

// MARK: - Time Range Filter

public enum MetricsTimeRange: String, CaseIterable, Identifiable {
  case day = "24h"
  case week = "7d"
  case month = "30d"
  case all = "All"

  public var id: String { rawValue }

  public var startDate: Date? {
    switch self {
    case .day: return Calendar.current.date(byAdding: .day, value: -1, to: Date())
    case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
    case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
    case .all: return nil
    }
  }
}
