import Foundation

public enum AgentModel: String, CaseIterable, Identifiable, Sendable {
  case sonnet = "Sonnet"
  case opus = "Opus"

  public var id: String { rawValue }

  public var label: String {
    "agent:\(rawValue.lowercased())"
  }

  public var description: String {
    switch self {
    case .opus: return "Best for complex features, multi-file refactors, and architectural changes."
    case .sonnet: return "Best for quick fixes, test additions, and straightforward changes."
    }
  }
}

public struct TicketAssignment {
  public var provider: Provider?
  public var ticketID: String = ""
  public var project: String = ""
  public var model: AgentModel = .opus

  public init(
    provider: Provider? = nil,
    ticketID: String = "",
    project: String = "",
    model: AgentModel = .opus
  ) {
    self.provider = provider
    self.ticketID = ticketID
    self.project = project
    self.model = model
  }
}

