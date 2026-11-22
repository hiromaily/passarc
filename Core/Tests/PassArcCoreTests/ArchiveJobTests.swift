import Foundation
import Synchronization
import Testing

@testable import PassArcCore

@Suite struct ArchiveJobTests {
  /// tmp/projects/a.txt and tmp/projects/sub/b.txt
  private func makeProjects() throws -> (dir: URL, projects: URL) {
    let dir = try TestSupport.makeTempDir()
    let projects = dir.appending(path: "projects")
    try TestSupport.write("alpha", to: projects.appending(path: "a.txt"))
    try TestSupport.write("beta", to: projects.appending(path: "sub/b.txt"))
    return (dir, projects)
  }

  private func leftovers(in dir: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("partial") }
  }

  private func sevenZip(_ args: [String], cwd: URL, password: String?) async throws -> PTYResult {
    try await PTYRunner(
      executable: TestSupport.sevenZip, arguments: args, currentDirectory: cwd, password: password
    ).run(onOutput: { _ in })
  }

  @Test(arguments: [ArchiveFormat.sevenZip, .zip])
  func job_createsVerifiedEncryptedArchive(format: ArchiveFormat) async throws {
    let (dir, projects) = try makeProjects()
    let job = ArchiveJob(
      request: ArchiveRequest(items: [projects], format: format, level: .normal, password: "pw"))
    let out = try await job.run(progress: { _ in })

    #expect(out.lastPathComponent == "projects.\(format.fileExtension)")
    #expect(FileManager.default.fileExists(atPath: out.path))
    #expect(try leftovers(in: dir).isEmpty)
    let ok = try await sevenZip(["t", "--", out.path], cwd: dir, password: "pw")
    #expect(ok.exitCode == 0, "\(ok.output)")
    let ng = try await sevenZip(["t", "--", out.path], cwd: dir, password: "nope")
    #expect(ng.exitCode != 0)
  }

  @Test func job_zipUsesAES256() async throws {
    let (_, projects) = try makeProjects()
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [projects], format: .zip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    let (_, listing) = try TestSupport.run(TestSupport.sevenZip, ["l", "-slt", "--", out.path])
    #expect(listing.contains("Method = AES-256"), "\(listing)")
  }

  @Test func job_createsTarZst() async throws {
    let (dir, projects) = try makeProjects()
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [projects], format: .tarZst, level: .normal, password: nil)
    ).run(progress: { _ in })
    #expect(out.lastPathComponent == "projects.tar.zst")

    let extract = dir.appending(path: "extract")
    try FileManager.default.createDirectory(at: extract, withIntermediateDirectories: true)
    let tarFile = dir.appending(path: "x.tar")
    try TestSupport.run(TestSupport.zstd, ["-d", "-q", "-o", tarFile.path, out.path])
    try TestSupport.run(URL(filePath: "/usr/bin/tar"), ["-x", "-f", tarFile.path, "-C", extract.path])
    let text = try String(contentsOf: extract.appending(path: "projects/a.txt"), encoding: .utf8)
    #expect(text == "alpha")
    #expect(try leftovers(in: dir).isEmpty)
  }

  @Test(arguments: [ArchiveFormat.sevenZip, .tarZst])
  func job_reportsVerifyingPhase(format: ArchiveFormat) async throws {
    let (_, projects) = try makeProjects()
    let phases = Mutex<[JobPhase]>([])
    _ = try await ArchiveJob(
      request: ArchiveRequest(
        items: [projects], format: format, level: .fast,
        password: format.supportsPassword ? "pw" : nil)
    ).run(progress: { p in phases.withLock { $0.append(p) } })
    #expect(phases.withLock { $0 }.contains(.verifying))
    #expect(phases.withLock { $0 }.last == .verifying)
  }

  @Test(arguments: [ArchiveFormat.sevenZip, .tarZst])
  func job_cancelRemovesPartial(format: ArchiveFormat) async throws {
    let dir = try TestSupport.makeTempDir()
    let big = dir.appending(path: "big")
    try FileManager.default.createDirectory(at: big, withIntermediateDirectories: true)
    var bytes = [UInt8](repeating: 0, count: 50 << 20)
    for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
    try Data(bytes).write(to: big.appending(path: "r.bin"))

    let job = ArchiveJob(
      request: ArchiveRequest(
        items: [big], format: format, level: .maximum,
        password: format.supportsPassword ? "pw" : nil))
    await #expect(throws: ArchiveError.cancelled) {
      try await job.run(progress: { p in if case .compressing = p { job.cancel() } })
    }
    #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "big.\(format.fileExtension)").path))
    #expect(try leftovers(in: dir).isEmpty)
  }

  @Test func job_cancelDuringAgeRemovesStagingAndPartialArchive() async throws {
    let (dir, projects) = try makeProjects()
    let fm = FileManager.default
    defer { try? fm.removeItem(at: dir) }
    let age = dir.appending(path: "slow-age")
    // AgeCommand passes --output and its path as the second and third arguments.
    try TestSupport.write(
      """
      #!/bin/sh
      set -eu
      printf unfinished > "$3"
      exec /bin/sleep 20
      """,
      to: age)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: age.path)
    let job = ArchiveJob(
      request: ArchiveRequest(items: [projects], format: .tarZstAge, level: .fast, password: "pw"),
      locate: { $0 == .age ? age : ToolLocator.locate($0) })

    let running = Task { try await job.run(progress: { _ in }) }
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(10)
    var partialExists = false
    while clock.now < deadline {
      partialExists = (try? leftovers(in: dir))?.contains { name in
        let staging = dir.appending(path: name)
        return fm.fileExists(atPath: staging.appending(path: "encrypted.partial").path)
      } ?? false
      if partialExists { break }
      try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(partialExists)

    let cancelledAt = clock.now
    job.cancel()
    await #expect(throws: ArchiveError.cancelled) { try await running.value }
    #expect(clock.now - cancelledAt < .seconds(10))
    #expect(try leftovers(in: dir).isEmpty)
    #expect(!fm.fileExists(atPath: dir.appending(path: "projects.tar.zst.age").path))
  }

  @Test func job_failsCleanlyInReadOnlyDirectory() async throws {
    let (dir, projects) = try makeProjects()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

    do {
      _ = try await ArchiveJob(
        request: ArchiveRequest(items: [projects], format: .sevenZip, level: .fast, password: "hunter2")
      ).run(progress: { _ in })
      Issue.record("should fail")
    } catch let error as ArchiveError {
      guard case .failed = error else { Issue.record("expected .failed: \(error)"); return }
      #expect(!error.message.contains("hunter2"))  // job_errorNeverContainsPassword
      #expect(!error.message.isEmpty)
    }
    #expect(try leftovers(in: dir).isEmpty)
  }

  @Test func job_archivesEmptyDirectory() async throws {
    let dir = try TestSupport.makeTempDir()
    let empty = dir.appending(path: "empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [empty], format: .sevenZip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    #expect(out.lastPathComponent == "empty.7z")
  }

  @Test func job_handlesDashAndJapaneseNames() async throws {
    let dir = try TestSupport.makeTempDir()
    let dash = dir.appending(path: "-report")
    let jp = dir.appending(path: "売上 2026")
    try TestSupport.write("d", to: dash)
    try TestSupport.write("j", to: jp.appending(path: "q.txt"))

    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [dash, jp], format: .sevenZip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    #expect(out.lastPathComponent == "Archive.7z")
    let listing = try await sevenZip(["l", "--", out.path], cwd: dir, password: "pw")
    #expect(listing.output.contains("-report"))
    #expect(listing.output.contains("売上 2026"))
  }

  @Test func job_excludesMetadataFiles() async throws {
    let (dir, projects) = try makeProjects()
    try TestSupport.write("x", to: projects.appending(path: ".DS_Store"))
    try TestSupport.write("x", to: projects.appending(path: "._a.txt"))
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [projects], format: .sevenZip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    let listing = try await sevenZip(["l", "--", out.path], cwd: dir, password: "pw")
    #expect(!listing.output.contains(".DS_Store"))
    #expect(!listing.output.contains("._a.txt"))
  }

  @Test func job_toolMissing() async throws {
    let (_, projects) = try makeProjects()
    let job = ArchiveJob(
      request: ArchiveRequest(items: [projects], format: .sevenZip, level: .normal, password: "pw"),
      locate: { _ in nil })
    await #expect(throws: ArchiveError.toolMissing(.sevenZip)) {
      try await job.run(progress: { _ in })
    }
    #expect(
      ArchiveError.toolMissing(.sevenZip).message
        == "7zz was not found. Install it in Terminal with: brew install sevenzip")
  }

  /// What ArchiveJob creates must open with the password given on the command line
  @Test(arguments: [ArchiveFormat.sevenZip, .zip])
  func job_passwordOpensWithOtherTools(format: ArchiveFormat) async throws {
    let (dir, projects) = try makeProjects()
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [projects], format: format, level: .normal, password: "hello")
    ).run(progress: { _ in })
    let (code, output) = try TestSupport.run(
      TestSupport.sevenZip, ["t", "-phello", "--", out.path], cwd: dir)
    #expect(code == 0, "\(output)")
  }

  // MARK: - Findings from the final review

  @Test(arguments: [ArchiveFormat.sevenZip, .zip])
  func job_archivesSingleFile(format: ArchiveFormat) async throws {
    let dir = try TestSupport.makeTempDir()
    let file = dir.appending(path: "report.pdf")
    try TestSupport.write("pdf", to: file)
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [file], format: format, level: .normal, password: "pw")
    ).run(progress: { _ in })
    #expect(out.lastPathComponent == "report.pdf.\(format.fileExtension)")
  }

  @Test func job_archivesSingleEmptyFile() async throws {
    let dir = try TestSupport.makeTempDir()
    let file = dir.appending(path: "zero.bin")
    try TestSupport.write("", to: file)
    _ = try await ArchiveJob(
      request: ArchiveRequest(items: [file], format: .sevenZip, level: .normal, password: "pw")
    ).run(progress: { _ in })
  }

  @Test func job_archivesSeveralFilesWithoutFolder() async throws {
    let dir = try TestSupport.makeTempDir()
    let a = dir.appending(path: "a.txt"), b = dir.appending(path: "b.txt")
    try TestSupport.write("a", to: a)
    try TestSupport.write("b", to: b)
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [a, b], format: .zip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    #expect(out.lastPathComponent == "Archive.zip")
  }

  @Test func job_tarZstFailsCleanlyInReadOnlyDirectory() async throws {
    // The test runner ignores SIGPIPE. Restore the default (terminate), as in the app.
    let previous = signal(SIGPIPE, SIG_DFL)
    defer { signal(SIGPIPE, previous) }
    let (dir, projects) = try makeProjects()
    // Writes that fit in the 64 KB pipe buffer never fail, so add a large file
    try Data(count: 2 << 20).write(to: projects.appending(path: "big.bin"))
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    await #expect(throws: ArchiveError.self) {
      try await ArchiveJob(
        request: ArchiveRequest(items: [projects], format: .tarZst, level: .fast, password: nil)
      ).run(progress: { _ in })
    }
    #expect(try leftovers(in: dir).isEmpty)
  }

  @Test func job_rejectsItemsFromDifferentFolders() async throws {
    let dir = try TestSupport.makeTempDir()
    let a = dir.appending(path: "sub/readme.txt"), b = dir.appending(path: "other.txt")
    try TestSupport.write("r", to: a)
    try TestSupport.write("o", to: b)
    await #expect(throws: ArchiveError.itemsInDifferentFolders) {
      try await ArchiveJob(
        request: ArchiveRequest(items: [a, b], format: .sevenZip, level: .normal, password: "pw")
      ).run(progress: { _ in })
    }
    #expect(
      ArchiveError.itemsInDifferentFolders.message
        == "Select items that are in the same folder.")
  }

  @Test func job_treatsWildcardCharactersLiterally() async throws {
    let dir = try TestSupport.makeTempDir()
    let q = dir.appending(path: "What?.txt")
    try TestSupport.write("q", to: q)
    try TestSupport.write("x", to: dir.appending(path: "Whatx.txt"))
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [q], format: .sevenZip, level: .normal, password: "pw")
    ).run(progress: { _ in })
    let listing = try await sevenZip(["l", "--", out.path], cwd: dir, password: "pw")
    #expect(listing.output.contains("What?.txt"))
    #expect(!listing.output.contains("Whatx.txt"))
  }

  @Test func job_tarZstKeepsNamesStartingWithAt() async throws {
    let dir = try TestSupport.makeTempDir()
    let at = dir.appending(path: "@notes")
    try TestSupport.write("n", to: at)
    let out = try await ArchiveJob(
      request: ArchiveRequest(items: [at], format: .tarZst, level: .fast, password: nil)
    ).run(progress: { _ in })
    let tarFile = dir.appending(path: "x.tar")
    try TestSupport.run(TestSupport.zstd, ["-d", "-q", "-o", tarFile.path, out.path])
    let (_, listing) = try TestSupport.run(URL(filePath: "/usr/bin/tar"), ["-t", "-f", tarFile.path])
    #expect(listing.contains("@notes"), "\(listing)")
  }

  @Test func job_parallelJobsDoNotCollide() async throws {
    let dir = try TestSupport.makeTempDir()
    let a = dir.appending(path: "a.txt"), b = dir.appending(path: "b.txt")
    try TestSupport.write("a", to: a)
    try TestSupport.write("b", to: b)
    let request = ArchiveRequest(items: [a, b], format: .sevenZip, level: .normal, password: "pw")
    async let first = ArchiveJob(request: request).run(progress: { _ in })
    async let second = ArchiveJob(request: request).run(progress: { _ in })
    let outs = try await [first, second].map(\.lastPathComponent).sorted()
    #expect(outs == ["Archive 2.7z", "Archive.7z"])
  }

  @Test func job_errorDoesNotHintAtShortPassword() async throws {
    let (dir, projects) = try makeProjects()
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    do {
      _ = try await ArchiveJob(
        request: ArchiveRequest(items: [projects], format: .sevenZip, level: .fast, password: "e")
      ).run(progress: { _ in })
      Issue.record("should fail")
    } catch let error as ArchiveError {
      #expect(!error.message.contains("••••"), "\(error.message)")
    }
  }
}
