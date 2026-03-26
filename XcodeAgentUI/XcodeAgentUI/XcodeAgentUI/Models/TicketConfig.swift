import Foundation

enum AgentModel: String, CaseIterable, Identifiable {
  case sonnet = "Sonnet"
  case opus = "Opus"

  var id: String { rawValue }

  var label: String {
    "agent:\(rawValue.lowercased())"
  }

  var description: String {
    switch self {
    case .opus: return "Best for complex features, multi-file refactors, and architectural changes."
    case .sonnet: return "Best for quick fixes, test additions, and straightforward changes."
    }
  }
}

struct TicketAssignment {
  var provider: Provider?
  var ticketID: String = ""
  var project: String = ""
  var model: AgentModel = .opus
}
