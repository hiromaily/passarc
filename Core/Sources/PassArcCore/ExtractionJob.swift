import Darwin
import Foundation
import Synchronization

public enum ExtractionError: LocalizedError, Equatable, Sendable {
  case unsupportedArchive
  case toolMissing(Tool)
  case passwordRequired
  case incorrectPassword
  case invalidPassphrase
  case invalidAgeIdentity
  case ageIdentityRequired
  case ageIdentityPassphraseRequired
  case incorrectAgeIdentityPassphrase
  case ageIdentityDecryptionFailed
  case failed(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedArchive: "Choose a 7z, ZIP, tar.zst, or tar.zst.age archive."
    case .toolMissing(let tool): ArchiveError.toolMissing(tool).message
    case .passwordRequired: "Enter the archive password."
    case .incorrectPassword: "Incorrect password. Try again."
    case .invalidPassphrase: "Enter a passphrase of at most 1023 UTF-8 bytes without control characters."
    case .invalidAgeIdentity: "Choose an age or SSH private key file."
    case .ageIdentityRequired: "Choose the age identity file for this archive."
    case .ageIdentityPassphraseRequired: "Enter the passphrase for the SSH private key."
    case .incorrectAgeIdentityPassphrase: "Incorrect SSH private key passphrase. Try again."
    case .ageIdentityDecryptionFailed: "Could not decrypt this archive with the selected age identity."
    case .failed(let detail): "Extraction failed.\n\(detail)"
    }
  }
}

public struct ExtractionJob: Sendable {
  private let archive: URL
  private let password: String?
  private let ageIdentity: URL?
  private let locate: @Sendable (Tool) -> URL?

  public init(
    archive: URL, password: String? = nil, ageIdentity: URL? = nil,
    locate: @escaping @Sendable (Tool) -> URL? = { ToolLocator.locate($0) }
  ) {
    self.archive = archive
    self.password = password
    self.ageIdentity = ageIdentity
    self.locate = locate
  }

  public static func format(of archive: URL) -> ArchiveFormat? {
    let name = archive.lastPathComponent.lowercased()
    return ArchiveFormat.allCases.first { name.hasSuffix("." + $0.fileExtension) }
  }

  public func run() async throws -> URL {
    guard let format = Self.format(of: archive),
          try archive.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    else { throw ExtractionError.unsupportedArchive }
    let tool = format.payload.tool
    guard let executable = locate(tool) else { throw ExtractionError.toolMissing(tool) }
    let age: URL?
    switch format.encryption {
    case .none, .sevenZipPassword:
      age = nil
    case .age:
      guard let executable = locate(.age) else { throw ExtractionError.toolMissing(.age) }
      if let ageIdentity {
        guard (try? AgeCommand.isSupportedIdentityFile(ageIdentity)) == true else {
          throw ExtractionError.invalidAgeIdentity
        }
      } else {
        guard let password, !password.isEmpty else { throw ExtractionError.passwordRequired }
      }
      if let password {
        guard password.utf8.count <= AgeCommand.maximumPassphraseBytes,
              password.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7F })
        else { throw ExtractionError.invalidPassphrase }
      }
      age = executable
    }

    try Task.checkCancellation()
    let fm = FileManager.default
    let parent = archive.deletingLastPathComponent()
    let staging = parent.appending(path: ".passarc-\(UUID().uuidString).partial", directoryHint: .isDirectory)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: staging) }
    let payload = staging.appending(path: "contents", directoryHint: .isDirectory)
    try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

    var compressed = archive
    if let age {
      compressed = staging.appending(path: "archive.tar.zst")
      let runner: PTYRunner
      if let ageIdentity {
        runner = AgeCommand.identityRunner(
          executable: age, input: archive, output: compressed, identity: ageIdentity, passphrase: password)
      } else {
        runner = AgeCommand.runner(
          executable: age, decrypt: true, input: archive, output: compressed, password: password ?? "")
      }
      let result = try await run(runner)
      if result.exitCode != 0 {
        if ageIdentity != nil {
          if result.output.split(whereSeparator: \.isNewline).contains(where: AgeCommand.isIdentityPassphrasePrompt) {
            if password?.isEmpty != false { throw ExtractionError.ageIdentityPassphraseRequired }
            if result.output.contains("incorrect passphrase") || result.output.contains("decryption password incorrect") {
              throw ExtractionError.incorrectAgeIdentityPassphrase
            }
          }
          throw ExtractionError.ageIdentityDecryptionFailed
        }
        if result.output.contains("identities are required") { throw ExtractionError.ageIdentityRequired }
        if result.output.contains("incorrect passphrase") { throw ExtractionError.incorrectPassword }
        throw ExtractionError.failed("age could not decrypt this archive with a passphrase.")
      }
    }

    switch format.payload {
    case .tarZst:
      try await extractTarZst(zstd: executable, compressed: compressed, staging: staging, payload: payload)
    case .sevenZip:
      let result = try await run(
        executable, ["x", "-y", "-bsp0", "-spd", "-t\(format.fileExtension)", "--", archive.path],
        in: payload, password: password ?? "")
      // Unencrypted archives never ask. An empty reply lets 7zz exit without waiting for input.
      if result.exitCode != 0,
         result.output.split(separator: "\n").contains(where: {
           $0.trimmingCharacters(in: .whitespaces) == "Enter password:"
         }) {
        throw password == nil ? ExtractionError.passwordRequired : ExtractionError.incorrectPassword
      }
      try check(result)
    }

    let basename = String(archive.lastPathComponent.dropLast(format.fileExtension.count + 1))
    let stem = basename.isEmpty || basename == "." || basename == ".." ? "Extracted Archive" : basename
    var occupied = Set<URL>()
    while true {
      try Task.checkCancellation()
      let destination = OutputNaming.firstFree(in: parent, stem: stem, suffix: "") {
        occupied.contains($0) || fm.fileExists(atPath: $0.path)
      }
      // The exclusive rename also handles collisions with other apps and dangling symlinks.
      if renamex_np(payload.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return destination }
      let code = errno
      guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
      occupied.insert(destination)
    }
  }

  private func extractTarZst(zstd: URL, compressed: URL, staging: URL, payload: URL) async throws {
    let stream = Pipe()
    // tar can finish at the end-of-archive marker before zstd has validated the full input.
    let remainingFD = fcntl(stream.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0)
    guard remainingFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    let remaining = FileHandle(fileDescriptor: remainingFD, closeOnDealloc: true)
    // Capture diagnostics in staging so either process can write freely while we wait for both.
    let diagnostics = staging.appending(path: "extraction.log")
    try Data().write(to: diagnostics)
    let errors = try FileHandle(forWritingTo: diagnostics)
    defer { try? errors.close() }

    let tar = Process()
    tar.executableURL = URL(filePath: "/usr/bin/tar")
    tar.arguments = ["-x", "-f", "-"]
    tar.currentDirectoryURL = payload
    tar.standardInput = stream
    tar.standardOutput = FileHandle.nullDevice
    tar.standardError = errors

    let decompress = Process()
    decompress.executableURL = zstd
    decompress.arguments = ["-d", "-q", "-c", "--", compressed.path]
    decompress.currentDirectoryURL = staging
    decompress.standardInput = FileHandle.nullDevice
    decompress.standardOutput = stream
    decompress.standardError = errors

    let cancelled = Mutex(false)
    try await withTaskCancellationHandler {
      let launched = try cancelled.withLock { cancelled in
        if cancelled { throw CancellationError() }
        try tar.run()
        // Foundation closes its copy of each pipe endpoint when the corresponding process starts.
        return Result { try decompress.run() }
      }
      if case .failure = launched {
        try? stream.fileHandleForWriting.close()
        if tar.isRunning { tar.terminate() }
      }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        Thread {
          tar.waitUntilExit()
          if case .success = launched, tar.terminationStatus == 0 {
            while let chunk = try? remaining.read(upToCount: 64 * 1024), !chunk.isEmpty {}
          }
          try? remaining.close()
          if case .success = launched { decompress.waitUntilExit() }
          continuation.resume()
        }.start()
      }
      try Task.checkCancellation()
      try launched.get()
      if decompress.terminationStatus != 0 || tar.terminationStatus != 0 {
        let output = String(decoding: try Data(contentsOf: diagnostics), as: UTF8.self)
        throw ExtractionError.failed(output.split(separator: "\n").suffix(12).joined(separator: "\n"))
      }
    } onCancel: {
      cancelled.withLock { cancelled in
        cancelled = true
        if decompress.isRunning { decompress.terminate() }
        if tar.isRunning { tar.terminate() }
      }
    }
  }

  private func run(
    _ executable: URL, _ arguments: [String], in directory: URL, password: String? = nil
  ) async throws -> PTYResult {
    try await run(PTYRunner(
      executable: executable, arguments: arguments, currentDirectory: directory, password: password)
    )
  }

  private func run(_ runner: PTYRunner) async throws -> PTYResult {
    try Task.checkCancellation()
    let result = try await withTaskCancellationHandler {
      try await runner.run(onOutput: { _ in })
    } onCancel: {
      runner.terminate()
    }
    try Task.checkCancellation()
    return result
  }

  private func check(_ result: PTYResult) throws {
    guard result.exitCode == 0 else {
      throw ExtractionError.failed(result.output.split(separator: "\n").suffix(12).joined(separator: "\n"))
    }
  }
}
