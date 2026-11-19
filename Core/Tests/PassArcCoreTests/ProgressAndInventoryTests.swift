import Foundation
import Testing

@testable import PassArcCore

@Suite struct ProgressParserTests {
  @Test func fraction_readsLastPercent() {
    #expect(ProgressParser.fraction(from: "  3% 1 + a\n 45% 12 + b") == 0.45)
  }

  @Test func fraction_nilWithoutPercent() {
    #expect(ProgressParser.fraction(from: "Scanning") == nil)
  }
}

@Suite struct FileInventoryTests {
  @Test func scan_countsFilesAndSkipsMetadata() throws {
    let dir = try TestSupport.makeTempDir()
    let root = dir.appending(path: "p")
    try TestSupport.write("abc", to: root.appending(path: "a.txt"))
    try TestSupport.write("12345", to: root.appending(path: "sub/b.txt"))
    try TestSupport.write("x", to: root.appending(path: ".DS_Store"))
    try TestSupport.write("x", to: root.appending(path: "._a.txt"))
    try FileManager.default.createDirectory(
      at: root.appending(path: "sub2"), withIntermediateDirectories: true)

    let inv = try FileInventory.scan(items: [root])
    #expect(inv.fileCount == 2)
    #expect(inv.totalBytes == 8)
    #expect(inv.excludedNames == [".DS_Store", "._a.txt"])
  }

  @Test func scan_countsSymlinkWithoutFollowing() throws {
    let dir = try TestSupport.makeTempDir()
    let root = dir.appending(path: "p")
    try TestSupport.write("abc", to: root.appending(path: "a.txt"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "link"), withDestinationURL: URL(filePath: "/etc"))

    let inv = try FileInventory.scan(items: [root])
    #expect(inv.fileCount == 2)
  }

  @Test func scan_acceptsSingleFile() throws {
    let dir = try TestSupport.makeTempDir()
    let file = dir.appending(path: "report.pdf")
    try TestSupport.write("abcd", to: file)
    let inv = try FileInventory.scan(items: [file])
    #expect(inv.fileCount == 1)
    #expect(inv.totalBytes == 4)
  }
}
