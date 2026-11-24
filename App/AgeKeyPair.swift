import Foundation
import PassArcCore

struct AgeKeyPair: Sendable {
  static let directoryPath = ".config/passarc/keys"
  static let defaultLocation = AgeKeyPair(directory: FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(directoryPath, isDirectory: true))
  let directory: URL

  static let identityName = "passarc-identity.txt"
  private static let recipientName = "passarc-recipient.txt"

  var identity: URL { directory.appendingPathComponent(Self.identityName) }
  var recipient: URL { directory.appendingPathComponent(Self.recipientName) }
  var hasIdentity: Bool { exists(identity) }
  var hasRecipient: Bool { exists(recipient) }

  enum CreationError: LocalizedError {
    case existingFile, missingTool, keygenFailed

    var errorDescription: String? {
      switch self {
      case .existingFile: "A key file already exists in the default folder. Existing keys are kept."
      case .missingTool: "Install age with Homebrew to create a key pair."
      case .keygenFailed: "age-keygen could not create the key pair."
      }
    }
  }

  func create() throws {
    guard !hasIdentity, !hasRecipient else { throw CreationError.existingFile }
    guard let keygen = ToolLocator.locate(.ageKeygen) else { throw CreationError.missingTool }

    let files = FileManager.default
    let privatePermissions: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
    try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: privatePermissions)
    let staging = directory.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
    try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: privatePermissions)
    defer { try? files.removeItem(at: staging) }

    let staged = AgeKeyPair(directory: staging)
    try run(keygen, arguments: ["-o", staged.identity.path])
    try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.identity.path)
    try run(keygen, arguments: ["-y", "-o", staged.recipient.path, staged.identity.path])

    // Hard links publish complete files and fail atomically if a destination exists.
    try files.linkItem(at: staged.identity, to: identity)
    do {
      try files.linkItem(at: staged.recipient, to: recipient)
    } catch {
      try? files.removeItem(at: identity)
      throw error
    }
  }

  private func exists(_ url: URL) -> Bool {
    let files = FileManager.default
    return files.fileExists(atPath: url.path) || (try? files.destinationOfSymbolicLink(atPath: url.path)) != nil
  }

  private func run(_ tool: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CreationError.keygenFailed }
  }
}
