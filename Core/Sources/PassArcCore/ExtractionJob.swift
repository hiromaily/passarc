import Darwin
import Foundation

public enum ExtractionError: LocalizedError, Equatable, Sendable {
  case unsupportedArchive
  case toolMissing(Tool)
  case passwordRequired
  case incorrectPassword
  case invalidPassphrase
  case failed(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedArchive: "Choose a 7z, ZIP, tar.zst, or tar.zst.age archive."
    case .toolMissing(let tool): ArchiveError.toolMissing(tool).message
    case .passwordRequired: "Enter the archive password."
    case .incorrectPassword: "Incorrect password. Try again."
    case .invalidPassphrase: "Enter a passphrase of at most 1023 UTF-8 bytes without control characters."
    case .failed(let detail): "Extraction failed.\n\(detail)"
    }
  }
}

public struct ExtractionJob: Sendable {
  private let archive: URL
  private let password: String?
  private let locate: @Sendable (Tool) -> URL?

  public init(
    archive: URL, password: String? = nil,
    locate: @escaping @Sendable (Tool) -> URL? = { ToolLocator.locate($0) }
  ) {
    self.archive = archive
    self.password = password
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
    let age: (executable: URL, password: String)?
    switch format.encryption {
    case .none, .sevenZipPassword:
      age = nil
    case .age:
      guard let executable = locate(.age) else { throw ExtractionError.toolMissing(.age) }
      guard let password, !password.isEmpty else { throw ExtractionError.passwordRequired }
      guard password.utf8.count <= AgeCommand.maximumPassphraseBytes,
        password.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7F })
      else { throw ExtractionError.invalidPassphrase }
      age = (executable, password)
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
      let result = try await run(AgeCommand.runner(
        executable: age.executable, decrypt: true, input: archive,
        output: compressed, password: age.password))
      if result.exitCode != 0 {
        if result.output.contains("incorrect passphrase") { throw ExtractionError.incorrectPassword }
        throw ExtractionError.failed("age could not decrypt this archive with a passphrase.")
      }
    }

    switch format.payload {
    case .tarZst:
      let tar = staging.appending(path: "archive.tar")
      try check(await run(executable, ["-d", "-q", "-o", tar.path, "--", compressed.path], in: staging))
      try check(await run(URL(filePath: "/usr/bin/tar"), ["-x", "-f", tar.path], in: payload))
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
