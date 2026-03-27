import SwiftUI
import XcodeAgentUICore
import UniformTypeIdentifiers

/// Feature 4: Code Review Assistant — side-by-side diff review with inline comments
public struct DiffReviewView: View {
  @Environment(AgentService.self) var agentService
  @State private var review = CodeReview(sessionID: UUID(), ticketID: "")
  @State private var selectedFileID: UUID?
  @State private var showExportSheet = false
  @State private var exportText = ""
  @State private var showBatchApproveConfirm = false
  @State private var showSubmitConfirm = false
  @State private var bridgeWS: BridgeWebSocket?

  public init() {}

  public var body: some View {
    VStack(spacing: 0) {
      reviewToolbar
      Divider()

      if review.files.isEmpty {
        emptyState
      } else {
        HSplitView {
          fileListPanel
            .frame(minWidth: 220, idealWidth: 260)
          diffDetailPanel
            .frame(minWidth: 500)
        }
      }
    }
    .onAppear { loadFromSession() }
    .sheet(isPresented: $showExportSheet) { exportSheet }
    .alert("Batch Approve", isPresented: $showBatchApproveConfirm) {
      Button("Approve All") {
        review.approveAll()
        sendReviewVerdict(approved: true)
        triggerHaptic()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Approve all \(review.files.count) files? This will mark every file as approved and send the verdict to the agent.")
    }
    .alert("Submit Review", isPresented: $showSubmitConfirm) {
      Button("Submit") {
        let approved = review.verdict == .approved
        sendReviewVerdict(approved: approved)
        triggerHaptic()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Submit this review as \"\(review.verdict.label)\" with \(review.totalComments) comment(s)?")
    }
  }

  // MARK: - Toolbar

  private var reviewToolbar: some View {
    HStack(spacing: 12) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.title2)
        .foregroundStyle(.cyan)

      Text("Code Review")
        .font(.headline)

      if !review.files.isEmpty {
        statsBar
      }

      Spacer()

      if !review.files.isEmpty {
        Button {
          showBatchApproveConfirm = true
        } label: {
          Label("Approve All", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(review.pendingCount == 0)

        Button {
          review.verdict = .changesRequested
          showSubmitConfirm = true
        } label: {
          Label("Request Changes", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .tint(.orange)

        Button {
          exportText = review.exportAsMarkdown()
          showExportSheet = true
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
      }

      Button {
        loadFromSession()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var statsBar: some View {
    HStack(spacing: 16) {
      HStack(spacing: 4) {
        Image(systemName: "doc.fill")
          .foregroundStyle(.secondary)
        Text("\(review.files.count) files")
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 4) {
        Circle().fill(.green).frame(width: 8, height: 8)
        Text("\(review.approvedCount)")
          .foregroundStyle(.green)
      }

      HStack(spacing: 4) {
        Circle().fill(.orange).frame(width: 8, height: 8)
        Text("\(review.changesRequestedCount)")
          .foregroundStyle(.orange)
      }

      HStack(spacing: 4) {
        Circle().fill(.secondary).frame(width: 8, height: 8)
        Text("\(review.pendingCount)")
          .foregroundStyle(.secondary)
      }

      if review.totalComments > 0 {
        HStack(spacing: 4) {
          Image(systemName: "bubble.left.fill")
            .foregroundStyle(.cyan)
          Text("\(review.totalComments)")
            .foregroundStyle(.cyan)
        }
      }
    }
    .font(.caption)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 48))
        .foregroundStyle(.tertiary)
      Text("No Diffs to Review")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("Start an agent session from Mission Control.\nFile changes will appear here for review.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.tertiary)
      Button("Refresh") { loadFromSession() }
        .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - File List Panel

  private var fileListPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Changed Files")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      List(selection: $selectedFileID) {
        ForEach(review.files) { file in
          fileRow(file)
            .tag(file.id)
        }
      }
      .listStyle(.sidebar)
    }
  }

  private func fileRow(_ file: ReviewFile) -> some View {
    HStack(spacing: 8) {
      statusIcon(for: file.status)

      VStack(alignment: .leading, spacing: 2) {
        Text(file.fileName)
          .font(.system(.body, design: .monospaced))
          .lineLimit(1)

        HStack(spacing: 8) {
          Text(file.filePath)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 2) {
        HStack(spacing: 4) {
          Text("+\(file.additions)")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.green)
          Text("-\(file.deletions)")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.red)
        }

        if !file.comments.isEmpty {
          HStack(spacing: 2) {
            Image(systemName: "bubble.left.fill")
              .font(.caption2)
            Text("\(file.comments.count)")
              .font(.caption2)
          }
          .foregroundStyle(.cyan)
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func statusIcon(for status: FileReviewStatus) -> some View {
    Image(systemName: status.icon)
      .font(.caption)
      .foregroundStyle(statusColor(status))
  }

  private func statusColor(_ status: FileReviewStatus) -> Color {
    switch status {
    case .pending: return .secondary
    case .approved: return .green
    case .changesRequested: return .orange
    }
  }

  // MARK: - Diff Detail Panel

  private var diffDetailPanel: some View {
    VStack(spacing: 0) {
      if let fileID = selectedFileID,
        let file = review.files.first(where: { $0.id == fileID })
      {
        fileDetailHeader(file)
        Divider()
        SideBySideDiffView(
          file: binding(for: fileID),
          review: review
        )
      } else {
        VStack(spacing: 12) {
          Image(systemName: "sidebar.left")
            .font(.system(size: 36))
            .foregroundStyle(.tertiary)
          Text("Select a file to review")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func fileDetailHeader(_ file: ReviewFile) -> some View {
    HStack(spacing: 12) {
      Image(systemName: fileIcon(for: file.fileExtension))
        .foregroundStyle(.cyan)

      Text(file.filePath)
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)

      Spacer()

      HStack(spacing: 4) {
        Text("+\(file.additions)")
          .foregroundStyle(.green)
        Text("-\(file.deletions)")
          .foregroundStyle(.red)
      }
      .font(.caption.weight(.semibold).monospacedDigit())

      Divider().frame(height: 20)

      Button {
        review.approveFile(id: file.id)
        sendFileVerdict(file: file, approved: true)
        triggerHaptic()
      } label: {
        Label("Approve", systemImage: "checkmark.circle")
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .controlSize(.small)
      .disabled(file.status == .approved)

      Button {
        review.requestChangesFile(id: file.id)
        sendFileVerdict(file: file, approved: false)
      } label: {
        Label("Request Changes", systemImage: "xmark.circle")
      }
      .buttonStyle(.bordered)
      .tint(.orange)
      .controlSize(.small)
      .disabled(file.status == .changesRequested)

      if file.status != .pending {
        Button {
          review.resetFile(id: file.id)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
  }

  // MARK: - Export Sheet

  private var exportSheet: some View {
    VStack(spacing: 16) {
      HStack {
        Text("Export Review")
          .font(.headline)
        Spacer()
        Button("Done") { showExportSheet = false }
          .buttonStyle(.bordered)
      }

      ScrollView {
        Text(exportText)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))

      HStack {
        Button("Copy to Clipboard") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(exportText, forType: .string)
        }
        .buttonStyle(.borderedProminent)

        Button("Save to File") {
          saveExport()
        }
        .buttonStyle(.bordered)

        Spacer()
      }
    }
    .padding(20)
    .frame(minWidth: 700, minHeight: 500)
  }

  // MARK: - Helpers

  private func binding(for fileID: UUID) -> Binding<ReviewFile> {
    Binding(
      get: { review.files.first(where: { $0.id == fileID }) ?? ReviewFile(filePath: "", hunks: []) },
      set: { newValue in
        if let idx = review.files.firstIndex(where: { $0.id == fileID }) {
          review.files[idx] = newValue
        }
      }
    )
  }

  private func loadFromSession() {
    guard let session = agentService.sessionManager.activeSession else { return }
    review.ingestDiffs(session.diffChunks)
    if bridgeWS == nil {
      bridgeWS = agentService.sharedBridgeWebSocket
    }
  }

  private func sendReviewVerdict(approved: Bool) {
    guard let ws = bridgeWS ?? makeBridgeWS() else { return }
    let payload = """
      {"approved": \(approved), "comments": \(review.totalComments), "files": \(review.files.count), "summary": "\(escapedSummary)"}
      """
    ws.send(type: "review_verdict", payload: payload)
  }

  private func sendFileVerdict(file: ReviewFile, approved: Bool) {
    guard let ws = bridgeWS ?? makeBridgeWS() else { return }
    let commentsJSON = file.comments.map {
      "{\"line\": \($0.line), \"content\": \"\(escapeJSON($0.content))\"}"
    }.joined(separator: ", ")
    let payload = """
      {"file": "\(file.filePath)", "approved": \(approved), "comments": [\(commentsJSON)]}
      """
    ws.send(type: "review_file_verdict", payload: payload)
  }

  private var escapedSummary: String {
    escapeJSON(review.summaryComment)
  }

  private func escapeJSON(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
  }

  private func makeBridgeWS() -> BridgeWebSocket? {
    let ws = BridgeWebSocket()
    ws.host = "localhost"
    ws.port = agentService.bridgePort
    ws.connect(role: .human, name: "code-reviewer")
    bridgeWS = ws
    return ws
  }

  private func saveExport() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "review-\(review.ticketID).md"
    if panel.runModal() == .OK, let url = panel.url {
      try? exportText.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  private func fileIcon(for ext: String) -> String {
    switch ext.lowercased() {
    case "swift": return "swift"
    case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
    case "py": return "text.word.spacing"
    case "json", "yaml", "yml", "toml": return "doc.text"
    case "md": return "doc.richtext"
    case "css", "scss": return "paintbrush"
    case "html": return "globe"
    default: return "doc"
    }
  }

  private func triggerHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
  }
}

// MARK: - Side-by-Side Diff View

struct SideBySideDiffView: View {
  @Binding var file: ReviewFile
  var review: CodeReview
  @State private var commentLineTarget: Int?
  @State private var commentText = ""
  @State private var hoveredLine: Int?

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ForEach(file.hunks) { hunk in
          hunkHeader(hunk)
          hunkContent(hunk)
        }
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
  }

  private func hunkHeader(_ hunk: DiffHunk) -> some View {
    HStack {
      Text(hunk.header)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.cyan)
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(Color.cyan.opacity(0.05))
  }

  private func hunkContent(_ hunk: DiffHunk) -> some View {
    let pairs = buildSideBySidePairs(hunk.lines)
    return VStack(spacing: 0) {
      ForEach(Array(pairs.enumerated()), id: \.offset) { entry in
        let pair = entry.element
        sideBySideRow(pair)
        inlineCommentsForLine(pair.rightLine ?? pair.leftLine ?? 0)
        if commentLineTarget == (pair.rightLine ?? pair.leftLine ?? -1) {
          commentInput(line: commentLineTarget!)
        }
      }
    }
  }

  private func sideBySideRow(_ pair: LinePair) -> some View {
    HStack(spacing: 0) {
      // Left pane (old)
      linePane(
        lineNumber: pair.leftLine,
        content: pair.leftContent,
        type: pair.leftType,
        isLeft: true,
        effectiveLine: pair.leftLine ?? pair.rightLine ?? 0
      )

      Divider()

      // Right pane (new)
      linePane(
        lineNumber: pair.rightLine,
        content: pair.rightContent,
        type: pair.rightType,
        isLeft: false,
        effectiveLine: pair.rightLine ?? pair.leftLine ?? 0
      )
    }
    .frame(minHeight: 20)
  }

  private func linePane(
    lineNumber: Int?, content: String?, type: DiffLine.LineType?, isLeft: Bool, effectiveLine: Int
  ) -> some View {
    HStack(spacing: 0) {
      // Line number gutter
      Text(lineNumber.map { String(format: "%4d", $0) } ?? "    ")
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.tertiary)
        .frame(width: 44, alignment: .trailing)
        .padding(.trailing, 4)

      // Change indicator
      Text(indicatorChar(type))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(indicatorColor(type))
        .frame(width: 14)

      // Content
      Text(content ?? "")
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(nil)

      // Comment button on right pane only
      if !isLeft {
        commentButton(line: effectiveLine)
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(lineBackground(type))
    .onHover { hovering in
      hoveredLine = hovering ? effectiveLine : nil
    }
  }

  private func commentButton(line: Int) -> some View {
    Button {
      if commentLineTarget == line {
        commentLineTarget = nil
      } else {
        commentLineTarget = line
        commentText = ""
      }
    } label: {
      Image(systemName: "plus.bubble")
        .font(.caption2)
        .foregroundStyle(hoveredLine == line ? .cyan : .clear)
    }
    .buttonStyle(.plain)
    .frame(width: 20)
  }

  private func inlineCommentsForLine(_ line: Int) -> some View {
    let lineComments = file.comments.filter { $0.line == line }
    return ForEach(lineComments, id: \.id) { comment in
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "bubble.left.fill")
          .font(.caption)
          .foregroundStyle(.cyan)
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(comment.author)
              .font(.caption.weight(.semibold))
            Text(timeString(comment.timestamp))
              .font(.caption2)
              .foregroundStyle(.tertiary)
            Spacer()
            Button {
              review.removeComment(fileID: file.id, commentID: comment.id)
            } label: {
              Image(systemName: "xmark")
                .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
          }
          Text(comment.content)
            .font(.system(.caption, design: .monospaced))
        }
      }
      .padding(.horizontal, 68)
      .padding(.vertical, 6)
      .background(Color.cyan.opacity(0.06))
    }
  }

  private func commentInput(line: Int) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "bubble.left")
        .font(.caption)
        .foregroundStyle(.cyan)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 6) {
        Text("Comment on line \(line)")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("Add a comment...", text: $commentText, axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(1...5)
          .padding(8)
          .background(Color(nsColor: .controlBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 6))

        HStack {
          Button("Comment") {
            review.addComment(fileID: file.id, line: line, content: commentText)
            commentText = ""
            commentLineTarget = nil
          }
          .buttonStyle(.borderedProminent)
          .tint(.cyan)
          .controlSize(.small)
          .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)

          Button("Cancel") {
            commentLineTarget = nil
            commentText = ""
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
    .padding(.horizontal, 68)
    .padding(.vertical, 8)
    .background(Color.cyan.opacity(0.04))
  }

  // MARK: - Line Pair Builder

  private func buildSideBySidePairs(_ lines: [DiffLine]) -> [LinePair] {
    var pairs: [LinePair] = []
    var i = 0

    while i < lines.count {
      let line = lines[i]
      switch line.type {
      case .context:
        pairs.append(
          LinePair(
            leftLine: line.lineNumber, leftContent: line.content, leftType: .context,
            rightLine: line.lineNumber, rightContent: line.content, rightType: .context
          ))
        i += 1

      case .deletion:
        // Look ahead for a matching addition
        if i + 1 < lines.count, lines[i + 1].type == .addition {
          let add = lines[i + 1]
          pairs.append(
            LinePair(
              leftLine: line.lineNumber, leftContent: line.content, leftType: .deletion,
              rightLine: add.lineNumber, rightContent: add.content, rightType: .addition
            ))
          i += 2
        } else {
          pairs.append(
            LinePair(
              leftLine: line.lineNumber, leftContent: line.content, leftType: .deletion,
              rightLine: nil, rightContent: nil, rightType: nil
            ))
          i += 1
        }

      case .addition:
        pairs.append(
          LinePair(
            leftLine: nil, leftContent: nil, leftType: nil,
            rightLine: line.lineNumber, rightContent: line.content, rightType: .addition
          ))
        i += 1
      }
    }
    return pairs
  }

  // MARK: - Styling Helpers

  private func indicatorChar(_ type: DiffLine.LineType?) -> String {
    switch type {
    case .addition: return "+"
    case .deletion: return "-"
    case .context, nil: return " "
    }
  }

  private func indicatorColor(_ type: DiffLine.LineType?) -> Color {
    switch type {
    case .addition: return .green
    case .deletion: return .red
    default: return .secondary
    }
  }

  private func lineBackground(_ type: DiffLine.LineType?) -> Color {
    switch type {
    case .addition: return .green.opacity(0.08)
    case .deletion: return .red.opacity(0.08)
    default: return .clear
    }
  }

  private func timeString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: date)
  }
}

/// A paired line for side-by-side display
struct LinePair {
  let leftLine: Int?
  let leftContent: String?
  let leftType: DiffLine.LineType?
  let rightLine: Int?
  let rightContent: String?
  let rightType: DiffLine.LineType?
}
