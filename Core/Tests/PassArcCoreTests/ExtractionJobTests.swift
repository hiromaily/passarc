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
}
