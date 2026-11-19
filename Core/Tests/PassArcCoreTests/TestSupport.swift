import Foundation

enum TestSupport {
  static let sevenZip = URL(filePath: "/opt/homebrew/bin/7zz")
  static let zstd = URL(filePath: "/opt/homebrew/bin/zstd")

  /// A new empty temp directory for each test
  static func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "passarc-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
  }

  static func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  /// Runs a plain Process (for checks that pass no password through a pty)
  @discardableResult
  static func run(_ exe: URL, _ args: [String], cwd: URL? = nil) throws -> (Int32, String) {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    if let cwd { p.currentDirectoryURL = cwd }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    p.standardInput = FileHandle.nullDevice
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
  }

  /// The command line (with arguments) of a pid
  static func processArguments(pid: Int32) -> String {
    (try? run(URL(filePath: "/bin/ps"), ["-ww", "-o", "args=", "-p", String(pid)]).1) ?? ""
  }
}
