import SwiftUI

/// Left panel: Live diff stream with syntax-highlighted code changes
struct DiffStreamView: View {
  var session: AgentSession

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Image(systemName: "doc.text.magnifyingglass")
          .foregroundColor(.accentColor)
        Text("Live Diff Stream")
          .font(.headline)
        Spacer()
        Text("\(session.diffChunks.count) files")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.bar)

      Divider()

      if session.diffChunks.isEmpty {
        emptyState
      } else {
        diffList
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 32))
        .foregroundColor(.secondary)
      Text("Waiting for code changes...")
        .foregroundColor(.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var diffList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(session.diffChunks) { chunk in
            DiffChunkView(chunk: chunk)
              .id(chunk.id)
          }
        }
        .padding(8)
      }
      .onChange(of: session.diffChunks.count) {
        if let last = session.diffChunks.last {
          withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

// MARK: - Diff Chunk

struct DiffChunkView: View {
  let chunk: DiffChunk

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // File header
      HStack(spacing: 6) {
        Image(systemName: iconForFile(chunk.filePath))
          .foregroundColor(.accentColor)
          .font(.caption)
        Text(chunk.filePath)
          .font(.system(.caption, design: .monospaced))
          .fontWeight(.semibold)
          .lineLimit(1)
        Spacer()
        Text(chunk.timestamp, style: .time)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.accentColor.opacity(0.1))

      // Hunks
      ForEach(chunk.hunks) { hunk in
        DiffHunkView(hunk: hunk)
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
  }

  private func iconForFile(_ path: String) -> String {
    if path.hasSuffix(".swift") { return "swift" }
    if path.hasSuffix(".ts") || path.hasSuffix(".js") { return "curlybraces" }
    if path.hasSuffix(".json") { return "doc.text" }
    if path.hasSuffix(".yml") || path.hasSuffix(".yaml") { return "list.bullet.rectangle" }
    if path.hasSuffix(".md") { return "doc.richtext" }
    return "doc"
  }
}

// MARK: - Diff Hunk

struct DiffHunkView: View {
  let hunk: DiffHunk

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !hunk.header.isEmpty {
        Text(hunk.header)
          .font(.system(.caption2, design: .monospaced))
          .foregroundColor(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.05))
      }

      ForEach(hunk.lines) { line in
        DiffLineView(line: line)
      }
    }
  }
}

// MARK: - Diff Line

struct DiffLineView: View {
  let line: DiffLine

  var body: some View {
    HStack(spacing: 0) {
      // Line number gutter
      Text(line.lineNumber.map { String(format: "%4d", $0) } ?? "    ")
        .font(.system(.caption2, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(width: 36, alignment: .trailing)
        .padding(.trailing, 4)

      // +/- indicator
      Text(prefix)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(color)
        .frame(width: 12)

      // Content
      Text(line.content)
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(color)
        .textSelection(.enabled)
        .lineLimit(nil)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 0.5)
    .background(backgroundColor)
  }

  private var prefix: String {
    switch line.type {
    case .addition: return "+"
    case .deletion: return "-"
    case .context: return " "
    }
  }

  private var color: Color {
    switch line.type {
    case .addition: return .green
    case .deletion: return .red
    case .context: return .primary
    }
  }

  private var backgroundColor: Color {
    switch line.type {
    case .addition: return Color.green.opacity(0.08)
    case .deletion: return Color.red.opacity(0.08)
    case .context: return .clear
    }
  }
}
