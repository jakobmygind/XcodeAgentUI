import SwiftUI
import XcodeAgentUICore

/// Bottom panel: Agent activity feed with output, errors, and inline approval buttons
struct AgentFeedView: View {
  var session: AgentSession
  let onApprove: (ApprovalRequest) -> Void
  let onDeny: (ApprovalRequest) -> Void

  @State private var filter: FeedFilter = .all

  enum FeedFilter: String, CaseIterable {
    case all = "All"
    case output = "Output"
    case errors = "Errors"
    case files = "Files"

    func matches(_ message: FeedMessage) -> Bool {
      switch self {
      case .all: return true
      case .output: return message.type == .output || message.type == .status
      case .errors: return message.type == .error
      case .files: return message.type == .fileChanged
      }
    }
  }

  private var filteredMessages: [FeedMessage] {
    session.feedMessages.filter { filter.matches($0) }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header with filters
      HStack {
        Image(systemName: "text.bubble")
          .foregroundColor(.purple)
        Text("Agent Activity")
          .font(.headline)

        Spacer()

        // Filter chips
        HStack(spacing: 4) {
          ForEach(FeedFilter.allCases, id: \.self) { f in
            FeedFilterChip(title: f.rawValue, isSelected: filter == f) {
              filter = f
            }
          }
        }

        Text("\(filteredMessages.count)")
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.15)))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      // Pending approval banner
      if let approval = session.pendingApproval {
        ApprovalBanner(request: approval, onApprove: onApprove, onDeny: onDeny)
      }

      // Messages
      if filteredMessages.isEmpty {
        emptyState
      } else {
        messageList
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Spacer()
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 24))
        .foregroundColor(.secondary)
      Text("Waiting for agent activity...")
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(filteredMessages) { message in
            FeedMessageRow(message: message)
              .id(message.id)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
      }
      .onChange(of: session.feedMessages.count) {
        if let last = filteredMessages.last {
          withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

// MARK: - Feed Message Row

struct FeedMessageRow: View {
  let message: FeedMessage

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: icon)
        .font(.caption2)
        .foregroundColor(color)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 1) {
        Text(message.content)
          .font(.system(.caption, design: .monospaced))
          .foregroundColor(textColor)
          .textSelection(.enabled)
          .lineLimit(8)
      }

      Spacer(minLength: 0)

      Text(message.timestamp, style: .time)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background(backgroundColor)
    .cornerRadius(4)
  }

  private var icon: String {
    switch message.type {
    case .output: return "text.alignleft"
    case .error: return "exclamationmark.triangle.fill"
    case .status: return "heart.fill"
    case .fileChanged: return "doc.fill"
    case .approval: return "questionmark.circle.fill"
    case .humanCommand: return "person.fill"
    case .system: return "gearshape.fill"
    }
  }

  private var color: Color {
    switch message.type {
    case .output: return .primary
    case .error: return .red
    case .status: return .green
    case .fileChanged: return .cyan
    case .approval: return .orange
    case .humanCommand: return .purple
    case .system: return .blue
    }
  }

  private var textColor: Color {
    message.type == .error ? .red : .primary
  }

  private var backgroundColor: Color {
    switch message.type {
    case .error: return Color.red.opacity(0.05)
    case .approval: return Color.orange.opacity(0.05)
    case .humanCommand: return Color.purple.opacity(0.05)
    default: return .clear
    }
  }
}

// MARK: - Approval Banner

struct ApprovalBanner: View {
  let request: ApprovalRequest
  let onApprove: (ApprovalRequest) -> Void
  let onDeny: (ApprovalRequest) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.shield.fill")
        .foregroundColor(.orange)
        .font(.title3)

      VStack(alignment: .leading, spacing: 2) {
        Text("Agent needs approval")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundColor(.orange)
        Text(request.description)
          .font(.caption)
          .lineLimit(2)
      }

      Spacer()

      Button(action: { onDeny(request) }) {
        Text("Deny")
          .font(.caption)
          .fontWeight(.medium)
      }
      .buttonStyle(.bordered)
      .tint(.red)

      Button(action: { onApprove(request) }) {
        Text("Approve")
          .font(.caption)
          .fontWeight(.medium)
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.1))
  }
}

// MARK: - Feed Filter Chip

struct FeedFilterChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.caption2)
        .fontWeight(isSelected ? .semibold : .regular)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
        .foregroundColor(isSelected ? .accentColor : .secondary)
        .cornerRadius(10)
    }
    .buttonStyle(.borderless)
  }
}
