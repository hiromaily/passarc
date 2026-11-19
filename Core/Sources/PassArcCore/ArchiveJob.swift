import Foundation
import Synchronization

public enum JobPhase: Equatable, Sendable {
  case compressing(Double?)
  case verifying
}

public enum ArchiveError: Error, Equatable, Sendable {
  case toolMissing(Tool)
  /// The tail of the tool's output
  case failed(String)
  case verificationFailed
  case cancelled
  /// The selected items are in different folders (e.g. from Finder search results)
  case itemsInDifferentFolders

  public var message: String {
    switch self {
    case .toolMissing(let tool):
      "\(tool.rawValue) was not found. Install it in Terminal with: brew install \(tool.brewPackage)"
    case .failed(let detail): "Compression failed.\n\(detail)"
    case .verificationFailed: "The new archive failed verification."
    case .cancelled: "Cancelled."
    case .itemsInDifferentFolders: "Select items that are in the same folder."
    }
  }
}

/// Compress, verify, then rename. On stop or failure, the partial file is deleted.
public final class ArchiveJob: @unchecked Sendable {
  private let request: ArchiveRequest
  private let locate: (Tool) -> URL?
  private let state = Mutex<(cancelled: Bool, stop: (@Sendable () -> Void)?)>((false, nil))
  /// Output and partial paths in use by running jobs in this process
  private static let reserved = Mutex<Set<String>>([])

  public init(request: ArchiveRequest, locate: @escaping (Tool) -> URL? = { ToolLocator.locate($0) }) {
    self.request = request
    self.locate = locate
  }

  public func cancel() {
    let stop = state.withLock { s -> (@Sendable () -> Void)? in
      s.cancelled = true
      return s.stop
    }
    stop?()
  }

  private var isCancelled: Bool { state.withLock { $0.cancelled } }

  /// Registers how to stop the running process. Stops it at once if already cancelled.
  private func setStop(_ stop: (@Sendable () -> Void)?) {
    let cancelledAlready = state.withLock { s -> Bool in
      s.stop = stop
      return s.cancelled
    }
    if cancelledAlready { stop?() }
  }

  public func run(progress: @escaping @Sendable (JobPhase) -> Void) async throws -> URL {
    let fm = FileManager.default
    let tool: Tool = request.format == .tarZst ? .zstd : .sevenZip
    guard let toolURL = locate(tool) else { throw ArchiveError.toolMissing(tool) }

    let inventory: FileInventory
    do {
      inventory = try FileInventory.scan(items: request.items)
    } catch {
      throw ArchiveError.failed(error.localizedDescription)
    }
    // 7zz and tar run in the parent folder with bare names, so all items must share it
    let parents = Set(request.items.map { $0.deletingLastPathComponent().standardizedFileURL.path })
    guard parents.count == 1 else { throw ArchiveError.itemsInDifferentFolders }

    // Reserve the output and partial names so parallel jobs never pick the same ones
    let (output, partial) = Self.reserved.withLock { taken -> (URL, URL) in
      let exists: (URL) -> Bool = { fm.fileExists(atPath: $0.path) || taken.contains($0.path) }
      let output = OutputNaming.outputURL(items: request.items, format: request.format, exists: exists)
      let partial = OutputNaming.partialURL(for: output, exists: exists)
      taken.insert(output.path)
      taken.insert(partial.path)
      return (output, partial)
    }
    defer { Self.reserved.withLock { $0.subtract([output.path, partial.path]) } }
    let cwd = request.items[0].deletingLastPathComponent()
    let names = request.items.map(\.lastPathComponent)

    do {
      if isCancelled { throw ArchiveError.cancelled }
      progress(.compressing(nil))
      if request.format == .tarZst {
        try await compressTarZst(
          zstd: toolURL, cwd: cwd, names: names, partial: partial,
          totalBytes: inventory.totalBytes, progress: progress)
      } else {
        try await compressSevenZip(
          sevenZip: toolURL, cwd: cwd, names: names, partial: partial,
          excludedNames: inventory.excludedNames, progress: progress)
      }
      if isCancelled { throw ArchiveError.cancelled }

      progress(.verifying)
      try await verify(tool: toolURL, partial: partial, expectedFiles: inventory.fileCount)
      if isCancelled { throw ArchiveError.cancelled }

      // If a file took the name while compressing, pick a free name (never overwrite)
      var final = output
      if fm.fileExists(atPath: final.path) {
        final = Self.reserved.withLock { taken in
          OutputNaming.outputURL(items: request.items, format: request.format) {
            fm.fileExists(atPath: $0.path) || (taken.contains($0.path) && $0 != output)
          }
        }
      }
      do {
        try fm.moveItem(at: partial, to: final)
      } catch {
        throw ArchiveError.failed(error.localizedDescription)
      }
      return final
    } catch {
      setStop(nil)
      try? fm.removeItem(at: partial)
      if isCancelled { throw ArchiveError.cancelled }
      throw error
    }
  }

  // MARK: - 7z / ZIP

  private func compressSevenZip(
    sevenZip: URL, cwd: URL, names: [String], partial: URL, excludedNames: Set<String>,
    progress: @escaping @Sendable (JobPhase) -> Void
  ) async throws {
    let list = FileManager.default.temporaryDirectory
      .appending(path: "passarc-exclude-\(UUID().uuidString).txt")
    do {
      try Data(CommandBuilder.excludeListContents(excludedNames).utf8).write(to: list)
    } catch {
      throw ArchiveError.failed(error.localizedDescription)
    }
    defer { try? FileManager.default.removeItem(at: list) }
    let args = CommandBuilder.sevenZipCreate(
      format: request.format, level: request.level, hasPassword: request.password != nil,
      archive: partial, excludeList: list, itemNames: names)
    let runner = PTYRunner(
      executable: sevenZip, arguments: args, currentDirectory: cwd, password: request.password)
    setStop { runner.terminate() }
    let result = try await runner.run(onOutput: { chunk in
      if let f = ProgressParser.fraction(from: chunk) { progress(.compressing(f)) }
    })
    setStop(nil)
    if isCancelled { throw ArchiveError.cancelled }
    if result.exitCode != 0 { throw ArchiveError.failed(sanitize(result.output)) }
  }

  // MARK: - tar.zst

  private func compressTarZst(
    zstd: URL, cwd: URL, names: [String], partial: URL, totalBytes: Int64,
    progress: @escaping @Sendable (JobPhase) -> Void
  ) async throws {
    let tar = Process()
    tar.executableURL = URL(filePath: "/usr/bin/tar")
    tar.arguments = CommandBuilder.tarCreate(itemNames: names)
    tar.currentDirectoryURL = cwd
    tar.environment = ProcessInfo.processInfo.environment.merging(CommandBuilder.tarEnvironment) { $1 }
    let tarOut = Pipe()
    let tarErr = Pipe()
    tar.standardOutput = tarOut
    tar.standardError = tarErr
    tar.standardInput = FileHandle.nullDevice

    let comp = Process()
    comp.executableURL = zstd
    comp.arguments = CommandBuilder.zstdCompress(level: request.level, output: partial)
    comp.currentDirectoryURL = cwd
    let compIn = Pipe()
    // If zstd exits early (e.g. the folder is not writable), writing would raise SIGPIPE and kill the app.
    // Turn it into a write error instead.
    _ = fcntl(compIn.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    let compErr = Pipe()
    comp.standardInput = compIn
    comp.standardOutput = FileHandle.nullDevice
    comp.standardError = compErr

    try comp.run()
    do {
      try tar.run()
    } catch {
      comp.terminate()
      throw ArchiveError.failed(error.localizedDescription)
    }
    setStop {
      if tar.isRunning { tar.terminate() }
      if comp.isRunning { comp.terminate() }
    }

    // Pump tar's output into zstd, counting bytes (progress = bytes sent / total size)
    let errors: (String, String) = await withCheckedContinuation { continuation in
      Thread {
        let reader = tarOut.fileHandleForReading
        let writer = compIn.fileHandleForWriting
        var sent: Int64 = 0
        var lastReported = -1
        while let data = try? reader.read(upToCount: 1 << 20), !data.isEmpty {
          do { try writer.write(contentsOf: data) } catch { break }
          sent += Int64(data.count)
          let pct = totalBytes > 0 ? min(100, Int(sent * 100 / totalBytes)) : 0
          if pct != lastReported {
            lastReported = pct
            progress(.compressing(Double(pct) / 100))
          }
        }
        try? writer.close()
        tar.waitUntilExit()
        comp.waitUntilExit()
        let tarMsg = String(decoding: tarErr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let compMsg = String(decoding: compErr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        continuation.resume(returning: (tarMsg, compMsg))
      }.start()
    }
    setStop(nil)
    if isCancelled { throw ArchiveError.cancelled }
    if tar.terminationStatus != 0 || comp.terminationStatus != 0 {
      throw ArchiveError.failed(sanitize(errors.0 + errors.1))
    }
  }

  // MARK: - Verification

  private func verify(tool: URL, partial: URL, expectedFiles: Int) async throws {
    if request.format == .tarZst {
      let runner = PTYRunner(
        executable: tool, arguments: CommandBuilder.zstdTest(archive: partial),
        currentDirectory: partial.deletingLastPathComponent(), password: nil)
      setStop { runner.terminate() }
      let result = try await runner.run(onOutput: { _ in })
      setStop(nil)
      if result.exitCode != 0 { throw ArchiveError.verificationFailed }
      return
    }
    let runner = PTYRunner(
      executable: tool, arguments: CommandBuilder.sevenZipTest(archive: partial),
      currentDirectory: partial.deletingLastPathComponent(), password: request.password)
    setStop { runner.terminate() }
    let result = try await runner.run(onOutput: { _ in })
    setStop(nil)
    if isCancelled { throw ArchiveError.cancelled }
    guard result.exitCode == 0, Self.testedFileCount(result.output) == expectedFiles else {
      throw ArchiveError.verificationFailed
    }
  }

  /// Number of "T <name>" lines from `7zz t -bb1`, excluding directories (ending in "/")
  static func testedFileCount(_ output: String) -> Int {
    output.split(separator: "\n").filter { $0.hasPrefix("T ") && !$0.hasSuffix("/") }.count
  }

  /// The last 20 lines. Echo is off, so the password is never in the output.
  /// (Masking text equal to the password would hint at the password.)
  private func sanitize(_ output: String) -> String {
    output.split(separator: "\n", omittingEmptySubsequences: true).suffix(20).joined(separator: "\n")
  }
}
