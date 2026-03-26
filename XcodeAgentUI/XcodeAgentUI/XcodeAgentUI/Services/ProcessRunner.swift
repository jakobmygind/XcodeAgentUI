import Combine
import Foundation

/// Runs shell processes and streams output
class ProcessRunner: ObservableObject {
  @Published var output: [String] = []
  @Published var isRunning = false

  private var process: Process?
  private var outputPipe: Pipe?
  private let maxLines = 5000

  var workingDirectory: String

  init(workingDirectory: String) {
    self.workingDirectory = workingDirectory
  }

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

    DispatchQueue.main.async {
      self.isRunning = true
      self.output = []
    }

    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
      let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
      DispatchQueue.main.async {
        self?.output.append(contentsOf: lines)
        if let count = self?.output.count, count > (self?.maxLines ?? 5000) {
          self?.output.removeFirst(count - (self?.maxLines ?? 5000))
        }
      }
    }

    proc.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        self?.isRunning = false
      }
    }

    do {
      try proc.run()
    } catch {
      DispatchQueue.main.async {
        self.output.append("[Error] Failed to start: \(error.localizedDescription)")
        self.isRunning = false
      }
    }
  }

  func stop() {
    if let proc = process, proc.isRunning {
      proc.terminate()
    }
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    process = nil
    outputPipe = nil
    DispatchQueue.main.async {
      self.isRunning = false
    }
  }
}
