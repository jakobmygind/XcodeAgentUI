import Foundation

public enum ServiceState: String, Sendable {
  case stopped = "Stopped"
  case starting = "Starting"
  case running = "Running"
  case error = "Error"

  public var color: String {
    switch self {
    case .stopped: return "gray"
    case .starting: return "yellow"
    case .running: return "green"
    case .error: return "red"
    }
  }
}

public struct ServiceStatus: Identifiable {
  public let id: String
  public let name: String
  public var state: ServiceState
  public var port: Int?
  public var pid: Int32?
  public var uptime: Date?
  public var lastError: String?
}
