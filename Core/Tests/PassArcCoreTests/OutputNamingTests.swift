import Foundation
import Testing

@testable import PassArcCore

@Suite struct OutputNamingTests {
  private func exists(_ paths: Set<String>) -> (URL) -> Bool { { paths.contains($0.path) } }
  private let none: (URL) -> Bool = { _ in false }

  @Test func outputURL_directoryUsesItsName() {
    let url = OutputNaming.outputURL(
      items: [URL(filePath: "/x/projects-2026", directoryHint: .isDirectory)], format: .sevenZip,
      exists: none)
    #expect(url.path == "/x/projects-2026.7z")
  }

  @Test func outputURL_fileKeepsExtension() {
    let url = OutputNaming.outputURL(items: [URL(filePath: "/x/report.pdf")], format: .zip, exists: none)
    #expect(url.path == "/x/report.pdf.zip")
  }

  @Test func outputURL_multipleItemsUseArchive() {
    let url = OutputNaming.outputURL(
      items: [URL(filePath: "/x/a"), URL(filePath: "/x/b")], format: .tarZst, exists: none)
    #expect(url.path == "/x/Archive.tar.zst")
  }

  @Test func outputURL_numbersOnCollision() {
    let url = OutputNaming.outputURL(
      items: [URL(filePath: "/x/p")], format: .sevenZip, exists: exists(["/x/p.7z", "/x/p 2.7z"]))
    #expect(url.path == "/x/p 3.7z")
  }

  @Test func outputURL_numbersTarZstBeforeDoubleExtension() {
    let url = OutputNaming.outputURL(
      items: [URL(filePath: "/x/p")], format: .tarZst, exists: exists(["/x/p.tar.zst"]))
    #expect(url.path == "/x/p 2.tar.zst")
  }

  @Test func partialURL_appendsPartial() {
    #expect(OutputNaming.partialURL(for: URL(filePath: "/x/p.7z"), exists: none).path == "/x/p.7z.partial")
  }

  @Test func partialURL_avoidsExistingPartial() {
    let url = OutputNaming.partialURL(for: URL(filePath: "/x/p.7z"), exists: exists(["/x/p.7z.partial"]))
    #expect(url.path == "/x/p.7z 2.partial")
  }

  @Test func format_properties() {
    #expect(ArchiveFormat.sevenZip.fileExtension == "7z")
    #expect(ArchiveFormat.zip.fileExtension == "zip")
    #expect(ArchiveFormat.tarZst.fileExtension == "tar.zst")
    #expect(ArchiveFormat.tarZst.supportsPassword == false)
    #expect(ArchiveFormat.sevenZip.supportsPassword && ArchiveFormat.zip.supportsPassword)
  }
}
