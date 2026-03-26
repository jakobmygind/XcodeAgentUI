import Foundation
import Observation

@Observable
final class ProcessRunner: @unchecked Sendable {
  var output: [String] = []
  var isRunning = false
  var onRunningChanged: (@MainActor (Bool) -> Void)?

  private var process: Process?
  private var outputPipe: Pipe?
  private let maxLines = 5000

  var workingDirectory: String

  init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
  }

  @MainActor
  func run(command: String, arguments: [String] = [], environment: [String: String]? = nil) {
    stop()

    let proc = Process()
    let pipe = Pipe()

    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [command] + arguments
    proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    proc.standardOutput = pipe
    proc.standardError = pipe

    if let env = environment {
      var merged = ProcessInfo.processInfo.environment
      for (k, v) in env { merged[k] = v }
      proc.environment = merged
    }

    self.process = proc
    self.outputPipe = pipe

    isRunning = true
    output = []

    let maxLinesCapture = maxLines
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
      let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.output.append(contentsOf: lines)
        if self.output.count > maxLinesCapture {
          self.output.removeFirst(self.output.count - maxLinesCapture)
        }
      }
    }

    proc.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.isRunning = false
        self?.onRunningChanged?(false)
      }
    }

    do {
      try proc.run()
    } catch {
      output.append("[Error] Failed to start: \(error.localizedDescription)")
      isRunning = false
      onRunningChanged?(false)
    }
  }

  @MainActor
  func stop() {
    if let proc = process, proc.isRunning {
      proc.terminate()
    }
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    process = nil
    outputPipe = nil
    isRunning = false
  }
}
