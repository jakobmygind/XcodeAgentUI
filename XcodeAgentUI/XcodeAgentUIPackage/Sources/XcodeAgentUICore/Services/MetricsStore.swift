import Foundation
import Observation
import SQLite3

@Observable @MainActor
public final class MetricsStore {
  public var runs: [TicketRun] = []
  public var agentStats: [AgentStats] = []
  public var dailyMetrics: [DailyMetric] = []
  public var timeRange: MetricsTimeRange = .week {
    didSet { reload() }
  }

  private nonisolated(unsafe) var db: OpaquePointer?
  private let dbPath: String

  public init() {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let appDir = appSupport.appendingPathComponent("XcodeAgentUI", isDirectory: true)
    try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
    self.dbPath = appDir.appendingPathComponent("metrics.sqlite").path

    openDatabase()
    createTables()
    reload()
  }

  deinit {
    sqlite3_close(db)
  }

  // MARK: - Database Setup

  private func openDatabase() {
    if sqlite3_open(dbPath, &db) != SQLITE_OK {
      let errmsg = String(cString: sqlite3_errmsg(db)!)
      print("[MetricsStore] Failed to open database: \(errmsg)")
    }
  }

  private func createTables() {
    let sql = """
      CREATE TABLE IF NOT EXISTS ticket_runs (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL,
        project TEXT NOT NULL,
        agent_model TEXT NOT NULL,
        started_at REAL NOT NULL,
        finished_at REAL NOT NULL,
        outcome TEXT NOT NULL,
        build_succeeded INTEGER NOT NULL DEFAULT 0,
        tests_succeeded INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_runs_started ON ticket_runs(started_at);
      CREATE INDEX IF NOT EXISTS idx_runs_model ON ticket_runs(agent_model);
      """
    execute(sql)
  }

  // MARK: - Write

  public func record(_ run: TicketRun) {
    let sql = """
      INSERT OR REPLACE INTO ticket_runs
        (id, ticket_id, project, agent_model, started_at, finished_at,
         outcome, build_succeeded, tests_succeeded, retry_count,
         input_tokens, output_tokens)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, (run.id as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (run.ticketID as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 3, (run.project as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 4, (run.agentModel as NSString).utf8String, -1, nil)
    sqlite3_bind_double(stmt, 5, run.startedAt.timeIntervalSince1970)
    sqlite3_bind_double(stmt, 6, run.finishedAt.timeIntervalSince1970)
    sqlite3_bind_text(stmt, 7, (run.outcome.rawValue as NSString).utf8String, -1, nil)
    sqlite3_bind_int(stmt, 8, run.buildSucceeded ? 1 : 0)
    sqlite3_bind_int(stmt, 9, run.testsSucceeded ? 1 : 0)
    sqlite3_bind_int(stmt, 10, Int32(run.retryCount))
    sqlite3_bind_int(stmt, 11, Int32(run.inputTokens))
    sqlite3_bind_int(stmt, 12, Int32(run.outputTokens))

    sqlite3_step(stmt)

    reload()
  }

  // MARK: - Read

  public func reload() {
    runs = fetchRuns()
    agentStats = computeAgentStats(from: runs)
    dailyMetrics = computeDailyMetrics(from: runs)
  }

  private func fetchRuns() -> [TicketRun] {
    var sql = "SELECT * FROM ticket_runs"
    if timeRange.startDate != nil {
      sql += " WHERE started_at >= ?"
    }
    sql += " ORDER BY started_at DESC"

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }

    if let start = timeRange.startDate {
      sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
    }

    var results: [TicketRun] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let run = TicketRun(
        id: columnText(stmt, 0),
        ticketID: columnText(stmt, 1),
        project: columnText(stmt, 2),
        agentModel: columnText(stmt, 3),
        startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
        finishedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
        outcome: RunOutcome(rawValue: columnText(stmt, 6)) ?? .failure,
        buildSucceeded: sqlite3_column_int(stmt, 7) == 1,
        testsSucceeded: sqlite3_column_int(stmt, 8) == 1,
        retryCount: Int(sqlite3_column_int(stmt, 9)),
        inputTokens: Int(sqlite3_column_int(stmt, 10)),
        outputTokens: Int(sqlite3_column_int(stmt, 11))
      )
      results.append(run)
    }
    return results
  }

  private func computeAgentStats(from runs: [TicketRun]) -> [AgentStats] {
    var map: [String: AgentStats] = [:]
    for run in runs {
      var stats = map[run.agentModel] ?? AgentStats(model: run.agentModel)
      stats.totalRuns += 1
      if run.outcome == .success { stats.successes += 1 }
      if run.outcome == .failure { stats.failures += 1 }
      stats.totalDuration += run.durationSeconds
      stats.totalRetries += run.retryCount
      if run.buildSucceeded { stats.buildSuccesses += 1 }
      if run.testsSucceeded { stats.testSuccesses += 1 }
      stats.totalInputTokens += run.inputTokens
      stats.totalOutputTokens += run.outputTokens
      stats.totalCost += run.estimatedCost
      map[run.agentModel] = stats
    }
    return Array(map.values).sorted { $0.model < $1.model }
  }

  private func computeDailyMetrics(from runs: [TicketRun]) -> [DailyMetric] {
    let cal = Calendar.current
    var map: [String: (metric: DailyMetric, durations: [TimeInterval])] = [:]

    for run in runs {
      let dayStart = cal.startOfDay(for: run.startedAt)
      let key = "\(dayStart.timeIntervalSince1970)-\(run.agentModel)"

      var entry = map[key] ?? (
        metric: DailyMetric(date: dayStart, model: run.agentModel),
        durations: []
      )
      entry.metric.runs += 1
      if run.outcome == .success { entry.metric.successes += 1 }
      entry.metric.totalCost += run.estimatedCost
      entry.durations.append(run.durationSeconds)
      map[key] = entry
    }

    return map.values.map { entry in
      var m = entry.metric
      let avg =
        entry.durations.isEmpty
        ? 0 : entry.durations.reduce(0, +) / Double(entry.durations.count)
      m.avgDuration = avg
      return m
    }.sorted { $0.date < $1.date }
  }

  // MARK: - Seed Demo Data

  public func seedDemoData() {
    let models = ["sonnet", "opus"]
    let outcomes: [RunOutcome] = [.success, .success, .success, .success, .failure, .timeout]
    let projects = ["ios-app", "backend-api", "shared-lib"]
    let cal = Calendar.current

    for dayOffset in (0..<14).reversed() {
      let runsPerDay = Int.random(in: 2...6)
      for _ in 0..<runsPerDay {
        let model = models.randomElement()!
        let outcome = outcomes.randomElement()!
        let startHour = Int.random(in: 8...20)
        let durationMin = model == "opus" ? Int.random(in: 8...45) : Int.random(in: 3...20)
        let started = cal.date(
          byAdding: .hour, value: startHour,
          to: cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: Date()))!
        )!
        let finished = cal.date(byAdding: .minute, value: durationMin, to: started)!

        let run = TicketRun(
          id: UUID().uuidString,
          ticketID:
            "\(projects.randomElement()!.prefix(2).uppercased())-\(Int.random(in: 100...999))",
          project: projects.randomElement()!,
          agentModel: model,
          startedAt: started,
          finishedAt: finished,
          outcome: outcome,
          buildSucceeded: outcome == .success || Bool.random(),
          testsSucceeded: outcome == .success || (outcome != .failure && Bool.random()),
          retryCount: outcome == .success ? Int.random(in: 0...1) : Int.random(in: 1...4),
          inputTokens: model == "opus"
            ? Int.random(in: 20000...120000) : Int.random(in: 8000...50000),
          outputTokens: model == "opus"
            ? Int.random(in: 5000...40000) : Int.random(in: 2000...15000)
        )
        record(run)
      }
    }
  }

  // MARK: - Delete All

  public func clearAll() {
    execute("DELETE FROM ticket_runs;")
    reload()
  }

  // MARK: - Helpers

  private func execute(_ sql: String) {
    var errmsg: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
      if let errmsg = errmsg {
        print("[MetricsStore] SQL error: \(String(cString: errmsg))")
        sqlite3_free(errmsg)
      }
    }
  }

  private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
    if let text = sqlite3_column_text(stmt, index) {
      return String(cString: text)
    }
    return ""
  }
}
