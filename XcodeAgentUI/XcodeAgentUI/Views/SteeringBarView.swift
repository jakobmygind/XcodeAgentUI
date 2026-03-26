import SwiftUI

/// Persistent bottom bar: Natural language steering input for the agent
struct SteeringBarView: View {
  let isConnected: Bool
  let onSend: (String) -> Void

  @State private var inputText = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 10) {
      // Connection indicator
      Circle()
        .fill(isConnected ? Color.green : Color.red)
        .frame(width: 8, height: 8)
        .help(isConnected ? "Connected as human" : "Disconnected")

      // Input field
      TextField("Steer the agent... (⌘⏎ to send)", text: $inputText)
        .textFieldStyle(.plain)
        .font(.system(.body, design: .monospaced))
        .focused($isFocused)
        .onSubmit { send() }
        .onAppear { isFocused = true }

      // Quick actions
      Menu {
        Button("Pause agent") { onSend("/pause") }
        Button("Resume agent") { onSend("/resume") }
        Divider()
        Button("Show current file") { onSend("/status") }
        Button("Run tests") { onSend("/test") }
        Divider()
        Button("Abort task") { onSend("/abort") }
      } label: {
        Image(systemName: "ellipsis.circle")
          .foregroundColor(.secondary)
      }
      .menuStyle(.borderlessButton)
      .frame(width: 24)

      // Send button
      Button(action: send) {
        Image(systemName: "paperplane.fill")
          .foregroundColor(canSend ? .accentColor : .secondary)
      }
      .buttonStyle(.borderless)
      .disabled(!canSend)
      .keyboardShortcut(.return, modifiers: .command)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var canSend: Bool {
    isConnected && !inputText.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func send() {
    let text = inputText.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, isConnected else { return }
    onSend(text)
    inputText = ""
  }
}
