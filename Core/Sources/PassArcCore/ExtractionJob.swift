import Darwin
import Foundation

public enum ExtractionError: LocalizedError, Equatable, Sendable {
  case unsupportedArchive
  case toolMissing(Tool)
  case passwordRequired
  case incorrectPassword
  case failed(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedArchive: "Choose a 7z, ZIP, or tar.zst archive."
    case .toolMissing(let tool): ArchiveError.toolMissing(tool).message
    case .passwordRequired: "Enter the archive password."
    case .incorrectPassword: "Incorrect password. Try again."
    case .failed(let detail): "Extraction failed.\n\(detail)"
    }
  }
}

public struct ExtractionJob: Sendable {
  private let archive: URL
  private let password: String?

  public init(archive: URL, password: String? = nil) {
    self.archive = archive
    self.password = password
  }

  public static func format(of archive: URL) -> ArchiveFormat? {
    let name = archive.lastPathComponent.lowercased()
    return ArchiveFormat.allCases.first { name.hasSuffix("." + $0.fileExtension) }
  }

  public func run() async throws -> URL {
    guard let format = Self.format(of: archive),
      try archive.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    else { throw ExtractionError.unsupportedArchive }
    let tool: Tool = format == .tarZst ? .zstd : .sevenZip
    guard let executable = ToolLocator.locate(tool) else { throw ExtractionError.toolMissing(tool) }

    try Task.checkCancellation()
    let fm = FileManager.default
    let parent = archive.deletingLastPathComponent()
    let staging = parent.appending(path: ".passarc-\(UUID().uuidString).partial", directoryHint: .isDirectory)
    try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: staging) }
    let payload = staging.appending(path: "contents", directoryHint: .isDirectory)
    try fm.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

    if format == .tarZst {
      let tar = staging.appending(path: "archive.tar")
      try check(await run(executable, ["-d", "-q", "-o", tar.path, "--", archive.path], in: staging))
      try check(await run(URL(filePath: "/usr/bin/tar"), ["-x", "-f", tar.path], in: payload))
    } else {
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

  private func run(
    _ executable: URL, _ arguments: [String], in directory: URL, password: String? = nil
  ) async throws -> PTYResult {
    try Task.checkCancellation()
    let runner = PTYRunner(
      executable: executable, arguments: arguments, currentDirectory: directory, password: password)
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
