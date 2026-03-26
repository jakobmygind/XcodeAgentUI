import Foundation

enum ClientRole: String, Codable {
  case agent
  case human
  case observer
}

struct BridgeEnvelope: Codable, Identifiable {
  let id: UUID
  let type: String
  let from: String
  let ts: String
  let payload: AnyCodable

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = UUID()
    self.type = try container.decode(String.self, forKey: .type)
    self.from = try container.decode(String.self, forKey: .from)
    self.ts =
      try container.decodeIfPresent(String.self, forKey: .ts)
      ?? ISO8601DateFormatter().string(from: Date())
    self.payload =
      try container.decodeIfPresent(AnyCodable.self, forKey: .payload) ?? AnyCodable("")
  }

  enum CodingKeys: String, CodingKey {
    case type, from, ts, payload
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(from, forKey: .from)
    try container.encode(ts, forKey: .ts)
    try container.encode(payload, forKey: .payload)
  }
}

// Lightweight type-erased Codable wrapper
struct AnyCodable: Codable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let str = try? container.decode(String.self) {
      value = str
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues { $0.value }
    } else if let arr = try? container.decode([AnyCodable].self) {
      value = arr.map { $0.value }
    } else {
      value = ""
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case let str as String: try container.encode(str)
    case let int as Int: try container.encode(int)
    case let double as Double: try container.encode(double)
    case let bool as Bool: try container.encode(bool)
    default: try container.encode(String(describing: value))
    }
  }

  var stringValue: String {
    if let str = value as? String { return str }
    return String(describing: value)
  }
}

struct BridgeClient: Identifiable {
  let id = UUID()
  let role: String
  let name: String
}
