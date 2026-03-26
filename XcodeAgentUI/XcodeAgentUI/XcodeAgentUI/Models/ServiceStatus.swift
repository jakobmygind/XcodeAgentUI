import Foundation

enum ServiceState: String {
  case stopped = "Stopped"
  case starting = "Starting"
  case running = "Running"
  case error = "Error"

  var color: String {
    switch self {
    case .stopped: return "gray"
    case .starting: return "yellow"
    case .running: return "green"
    case .error: return "red"
    }
  }
}

struct ServiceStatus: Identifiable {
  let id: String
  let name: String
  var state: ServiceState
  var port: Int?
  var pid: Int32?
  var uptime: Date?
  var lastError: String?
}
