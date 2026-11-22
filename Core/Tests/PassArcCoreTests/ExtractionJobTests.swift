import Foundation
import Testing

@testable import PassArcCore

@Suite struct ExtractionJobTests {
  @Test(arguments: [ArchiveFormat.sevenZip, .zip, .tarZst])
  func extractsPassArcArchiveWithoutReplacingExistingFiles(format: ArchiveFormat) async throws {
    try await checkRoundTrip(format: format)
  }

  @Test(.enabled(if: ageExecutable != nil, "Install age to exercise encrypted tar.zst archives"))
  func extractsPassphraseEncryptedTarZst() async throws {
    let age = try #require(Self.ageExecutable)
    try await checkRoundTrip(format: .tarZstAge) { tool in
      tool == .age ? age : ToolLocator.locate(tool)
    }
  }

  private static let ageExecutable = ProcessInfo.processInfo.environment["PASSARC_TEST_AGE"]
    .map { URL(filePath: $0) } ?? ToolLocator.locate(.age)

  private func checkRoundTrip(
    format: ArchiveFormat, locate: @escaping @Sendable (Tool) -> URL? = { ToolLocator.locate($0) }
  ) async throws {
    let dir = try TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appending(path: "日本語 + files")
    let original = source.appending(path: "folder/file.txt")
    try TestSupport.write("original contents", to: original)
    let link = source.appending(path: "link")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "folder/file.txt")
    let password = format.supportsPassword ? "test password" : nil
    let archive = try await ArchiveJob(
      request: ArchiveRequest(items: [source], format: format, level: .fast, password: password),
      locate: locate
    ).run(progress: { _ in })
    #expect(ExtractionJob.format(of: archive) == format)

    if format.supportsPassword {
      await #expect(throws: ExtractionError.passwordRequired) {
        try await ExtractionJob(archive: archive, locate: locate).run()
      }
      await #expect(throws: ExtractionError.incorrectPassword) {
        try await ExtractionJob(archive: archive, password: "wrong", locate: locate).run()
      }
    }

    async let first = ExtractionJob(archive: archive, password: password, locate: locate).run()
    async let second = ExtractionJob(archive: archive, password: password, locate: locate).run()
    let destinations = try await [first, second]
    #expect(Set(destinations.map(\.lastPathComponent)) == ["日本語 + files 2", "日本語 + files 3"])
    for destination in destinations {
      let extracted = destination.appending(path: source.lastPathComponent)
      #expect(try String(contentsOf: extracted.appending(path: "folder/file.txt"), encoding: .utf8) == "original contents")
      #expect(try FileManager.default.destinationOfSymbolicLink(atPath: extracted.appending(path: "link").path) == "folder/file.txt")
    }
    #expect(try String(contentsOf: original, encoding: .utf8) == "original contents")
    if format == .tarZstAge {
      var tampered = try Data(contentsOf: archive)
      let lastByte = try #require(tampered.indices.last)
      tampered[lastByte] ^= 1
      let broken = dir.appending(path: "tampered.tar.zst.age")
      try tampered.write(to: broken)
      await #expect(throws: ExtractionError.self) {
        try await ExtractionJob(archive: broken, password: password, locate: locate).run()
      }
      #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "tampered").path))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasSuffix(".partial") })
  }

  @Test(arguments: [ArchiveFormat.sevenZip, .zip])
  func extractsUnprotectedArchivesWithoutAPassword(format: ArchiveFormat) async throws {
    let dir = try TestSupport.makeTempDir()
    let source = dir.appending(path: "hello.txt")
    try TestSupport.write("hello", to: source)
    let archive = try await ArchiveJob(
      request: ArchiveRequest(items: [source], format: format, level: .fast, password: nil)
    ).run(progress: { _ in })
    let extracted = try await ExtractionJob(archive: archive).run()
    #expect(try String(contentsOf: extracted.appending(path: "hello.txt"), encoding: .utf8) == "hello")
  }

  @Test func corruptArchiveLeavesNoOutput() async throws {
    let dir = try TestSupport.makeTempDir()
    let archive = dir.appending(path: "broken.zip")
    try TestSupport.write("invalid archive", to: archive)
    await #expect(throws: ExtractionError.self) {
      try await ExtractionJob(archive: archive).run()
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["broken.zip"])
  }

  @Test func validatesZstdFramesAfterTheTarEndMarker() async throws {
    let dir = try TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appending(path: "hello.txt")
    try TestSupport.write("hello", to: source)
    let archive = try await ArchiveJob(
      request: ArchiveRequest(items: [source], format: .tarZst, level: .fast, password: nil)
    ).run(progress: { _ in })

    let padding = dir.appending(path: "padding")
    try Data(count: 1024 * 1024).write(to: padding)
    let frame = dir.appending(path: "padding.zst")
    let zstd = try #require(ToolLocator.locate(.zstd))
    let (status, _) = try TestSupport.run(zstd, ["--check", "-o", frame.path, "--", padding.path])
    try #require(status == 0)
    var trailingFrame = try Data(contentsOf: frame)
    var archiveBytes = try Data(contentsOf: archive)
    archiveBytes.append(trailingFrame)
    try archiveBytes.write(to: archive)
    let extracted = try await ExtractionJob(archive: archive).run()
    #expect(try String(contentsOf: extracted.appending(path: "hello.txt"), encoding: .utf8) == "hello")

    let lastByte = try #require(trailingFrame.indices.last)
    trailingFrame[lastByte] ^= 1
    var corruptBytes = Data(archiveBytes.dropLast(trailingFrame.count))
    corruptBytes.append(trailingFrame)
    let broken = dir.appending(path: "broken.tar.zst")
    try corruptBytes.write(to: broken)
    await #expect(throws: ExtractionError.self) {
      try await ExtractionJob(archive: broken).run()
    }
    let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(!remaining.contains("broken"))
    #expect(!remaining.contains { $0.hasSuffix(".partial") })
  }

  @Test func cancelledTarZstExtractionRemovesStaging() async throws {
    let dir = try TestSupport.makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let archive = dir.appending(path: "cancel.tar.zst")
    try TestSupport.write("unused", to: archive)
    let fakeZstd = dir.appending(path: "zstd")
    try TestSupport.write("#!/bin/sh\ntouch ../started\nexec /bin/sleep 5\n", to: fakeZstd)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeZstd.path)
    let task = Task {
      try await ExtractionJob(archive: archive, locate: { _ in fakeZstd }).run()
    }
    defer { task.cancel() }
    let marker = dir.appending(path: "started")
    for _ in 0 ..< 200 where !FileManager.default.fileExists(atPath: marker.path) {
      try await Task.sleep(for: .milliseconds(10))
    }
    let started = FileManager.default.fileExists(atPath: marker.path)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(started)
    let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(Set(remaining) == ["cancel.tar.zst", "zstd", "started"])
  }
}
