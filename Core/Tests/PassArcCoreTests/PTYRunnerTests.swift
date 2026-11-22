import Foundation
import Synchronization
import Testing

@testable import PassArcCore

@Suite struct PTYRunnerTests {
  private func sevenZip(_ args: [String], cwd: URL, password: String?) async throws -> PTYResult {
    try await PTYRunner(
      executable: TestSupport.sevenZip, arguments: args, currentDirectory: cwd, password: password
    ).run(onOutput: { _ in })
  }

  @Test func pty_createsEncrypted7zWithoutPasswordInArguments() async throws {
    let dir = try TestSupport.makeTempDir()
    try TestSupport.write("hello", to: dir.appending(path: "a.txt"))

    let runner = PTYRunner(
      executable: TestSupport.sevenZip,
      arguments: ["a", "-t7z", "-mhe=on", "-p", "--", "out.7z", "a.txt"],
      currentDirectory: dir, password: "s3cret")
    let psArgs = Mutex<String>("")
    let result = try await runner.run(onOutput: { _ in
      let args = TestSupport.processArguments(pid: runner.processIdentifier)
      psArgs.withLock { if $0.isEmpty { $0 = args } }
    })

    #expect(result.exitCode == 0, "\(result.output)")
    #expect(!psArgs.withLock { $0 }.isEmpty)
    #expect(!psArgs.withLock { $0 }.contains("s3cret"))

    let testOK = try await sevenZip(["t", "--", "out.7z"], cwd: dir, password: "s3cret")
    let testNG = try await sevenZip(["t", "--", "out.7z"], cwd: dir, password: "wrong")
    #expect(testOK.exitCode == 0, "\(testOK.output)")
    #expect(testNG.exitCode != 0)

    let (_, listNoPass) = try TestSupport.run(
      TestSupport.sevenZip, ["l", "-p", "--", "out.7z"], cwd: dir)
    #expect(!listNoPass.contains("a.txt"))
  }

  @Test func pty_passesPasswordWithSymbols() async throws {
    let dir = try TestSupport.makeTempDir()
    try TestSupport.write("hello", to: dir.appending(path: "a.txt"))
    let password = #"a b"'\$!%&*()[]{}<>?~`"#

    let made = try await sevenZip(
      ["a", "-t7z", "-mhe=on", "-p", "--", "out.7z", "a.txt"], cwd: dir, password: password)
    #expect(made.exitCode == 0, "\(made.output)")
    let tested = try await sevenZip(["t", "--", "out.7z"], cwd: dir, password: password)
    #expect(tested.exitCode == 0, "\(tested.output)")
  }

  /// Create through the pty, check through argv. Checking through the same path would miss a garbled password.
  @Test func pty_passwordMatchesWhatOtherToolsUse() async throws {
    let dir = try TestSupport.makeTempDir()
    try TestSupport.write("hello", to: dir.appending(path: "a.txt"))
    let made = try await sevenZip(
      ["a", "-t7z", "-mhe=on", "-p", "--", "out.7z", "a.txt"], cwd: dir, password: "hello")
    #expect(made.exitCode == 0, "\(made.output)")
    let (code, output) = try TestSupport.run(
      TestSupport.sevenZip, ["t", "-phello", "--", "out.7z"], cwd: dir)
    #expect(code == 0, "\(output)")
  }

  /// Passwords longer than the tty line limit (MAX_CANON = 1024) must not hang
  @Test(.timeLimit(.minutes(1))) func pty_longPasswordDoesNotHang() async throws {
    let dir = try TestSupport.makeTempDir()
    try TestSupport.write("hello", to: dir.appending(path: "a.txt"))
    let password = String(repeating: "abcdefghij", count: 200) // 2000 characters
    let made = try await sevenZip(
      ["a", "-t7z", "-mhe=on", "-p", "--", "out.7z", "a.txt"], cwd: dir, password: password)
    #expect(made.exitCode == 0, "\(made.output)")
    let (code, output) = try TestSupport.run(
      TestSupport.sevenZip, ["t", "-p\(password)", "--", "out.7z"], cwd: dir)
    #expect(code == 0, "\(output)")
  }

  @Test func pty_symbolPasswordMatchesWhatOtherToolsUse() async throws {
    let dir = try TestSupport.makeTempDir()
    try TestSupport.write("hello", to: dir.appending(path: "a.txt"))
    let password = #" a b"'\$!%&*()[]{}<>?~` "#
    let made = try await sevenZip(
      ["a", "-t7z", "-mhe=on", "-p", "--", "out.7z", "a.txt"], cwd: dir, password: password)
    #expect(made.exitCode == 0, "\(made.output)")
    let (code, output) = try TestSupport.run(
      TestSupport.sevenZip, ["t", "-p\(password)", "--", "out.7z"], cwd: dir)
    #expect(code == 0, "\(output)")
  }
}
