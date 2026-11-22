import Darwin
import Foundation
import Synchronization

public struct PTYResult: Sendable {
  public let exitCode: Int32
  public let output: String
}

public enum PTYRunnerError: Error, Sendable {
  case openptyFailed(Int32)
}

/// Runs a command in a pseudo-terminal and answers its password prompts.
/// The password never appears in arguments or environment variables.
public final class PTYRunner: @unchecked Sendable {
  private let executable: URL
  private let arguments: [String]
  private let currentDirectory: URL
  private let environment: [String: String]?
  private let password: String?
  private let prompt: @Sendable (String) -> Bool
  private let process = Process()
  private let stopped = Mutex(false)

  public init(
    executable: URL, arguments: [String], currentDirectory: URL,
    environment: [String: String]? = nil, password: String?,
    prompt: (@Sendable (String) -> Bool)? = nil
  ) {
    self.executable = executable
    self.arguments = arguments
    self.currentDirectory = currentDirectory
    self.environment = environment
    self.password = password
    self.prompt = prompt ?? Self.isPasswordPrompt
  }

  public var processIdentifier: Int32 { process.processIdentifier }

  public func terminate() {
    stopped.withLock { stopped in
      stopped = true
      if process.isRunning { process.terminate() }
    }
  }

  /// Writes the password followed by a newline when the configured prompt appears.
  public func run(onOutput: @escaping @Sendable (String) -> Void) async throws -> PTYResult {
    var master: Int32 = -1
    var slave: Int32 = -1
    guard openpty(&master, &slave, nil, nil, nil) == 0 else {
      throw PTYRunnerError.openptyFailed(errno)
    }
    var attrs = termios()
    tcgetattr(slave, &attrs)
    // Canonical mode cuts lines at MAX_CANON (1024), so long passwords lose the newline and hang.
    // Turn off line editing, signals and translation; pass bytes through as written.
    attrs.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
    attrs.c_iflag &= ~tcflag_t(ICRNL | IXON)
    withUnsafeMutableBytes(of: &attrs.c_cc) { cc in
      cc[Int(VMIN)] = 1
      cc[Int(VTIME)] = 0
    }
    tcsetattr(slave, TCSANOW, &attrs)

    let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    if let environment {
      process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
    }
    process.standardInput = slaveHandle
    process.standardOutput = slaveHandle
    process.standardError = slaveHandle

    do {
      try stopped.withLock { stopped in
        if stopped { throw CancellationError() }
        try self.process.run()
      }
    } catch {
      close(master)
      close(slave)
      throw error
    }
    close(slave)

    let masterFD = master
    let process = self.process
    let password = self.password
    let prompt = self.prompt
    return await withCheckedContinuation { continuation in
      let thread = Thread {
        var all = Data()
        var pending = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
          let n = read(masterFD, &buffer, buffer.count)
          if n > 0 {
            let chunk = Data(buffer[0 ..< n])
            all.append(chunk)
            let text = String(decoding: chunk, as: UTF8.self)
              .replacingOccurrences(of: "\r\n", with: "\n")
              .replacingOccurrences(of: "\r", with: "\n")
            onOutput(text)
            pending += text
            if let password, prompt(pending) {
              let line = Array((password + "\n").utf8)
              _ = line.withUnsafeBufferPointer { write(masterFD, $0.baseAddress, $0.count) }
              pending = ""
            }
            // Keep only the text after the last newline (a prompt in progress)
            if let lastNewline = pending.lastIndex(of: "\n") {
              pending = String(pending[pending.index(after: lastNewline)...])
            }
          } else if n < 0 && errno == EINTR {
            continue
          } else {
            break // EOF, or the child closed the terminal (EIO)
          }
        }
        close(masterFD)
        process.waitUntilExit()
        let output = String(decoding: all, as: UTF8.self)
          .replacingOccurrences(of: "\r\n", with: "\n")
        continuation.resume(returning: PTYResult(exitCode: process.terminationStatus, output: output))
      }
      thread.start()
    }
  }

  /// A prompt is a last, unterminated line that contains "password" and ends with ":"
  static func isPasswordPrompt(_ pendingLine: String) -> Bool {
    let lastLine = pendingLine.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
    return lastLine.lowercased().contains("password")
      && lastLine.trimmingCharacters(in: .whitespaces).hasSuffix(":")
  }
}
