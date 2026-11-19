import Foundation
import Testing

@testable import PassArcCore

@Suite struct CommandBuilderTests {
  private let partial = URL(filePath: "/x/p.7z.partial")
  private let list = URL(filePath: "/t/exclude.txt")

  @Test func sevenZip_7zWithPassword() {
    #expect(
      CommandBuilder.sevenZipCreate(
        format: .sevenZip, level: .normal, hasPassword: true, archive: partial, excludeList: list, itemNames: ["p"])
        == [
          "a", "-t7z", "-mx=5", "-mmt=on", "-snl", "-bsp1", "-spd", "-scsUTF-8", "-xr@/t/exclude.txt",
          "-mhe=on", "-p", "--", "/x/p.7z.partial", "p",
        ])
  }

  @Test func sevenZip_zipWithPassword() {
    let args = CommandBuilder.sevenZipCreate(
      format: .zip, level: .normal, hasPassword: true, archive: partial, excludeList: list, itemNames: ["p"])
    #expect(args.contains("-tzip"))
    #expect(args.contains("-mem=AES256"))
    #expect(args.contains("-p"))
    #expect(!args.contains("-mhe=on"))
  }

  @Test func sevenZip_withoutPassword() {
    for format in [ArchiveFormat.sevenZip, .zip] {
      let args = CommandBuilder.sevenZipCreate(
        format: format, level: .normal, hasPassword: false, archive: partial, excludeList: list, itemNames: ["p"])
      #expect(!args.contains("-p"))
      #expect(!args.contains("-mhe=on"))
      #expect(!args.contains("-mem=AES256"))
    }
  }

  @Test func sevenZip_levels() {
    func mx(_ level: CompressionLevel) -> Bool {
      CommandBuilder.sevenZipCreate(
        format: .sevenZip, level: level, hasPassword: false, archive: partial, excludeList: list, itemNames: ["p"]
      ).contains(["fast": "-mx=1", "normal": "-mx=5", "maximum": "-mx=9"][level.rawValue]!)
    }
    #expect(mx(.fast) && mx(.normal) && mx(.maximum))
  }

  @Test func sevenZipArguments_putsDoubleDashBeforePaths() {
    let args = CommandBuilder.sevenZipCreate(
      format: .sevenZip, level: .normal, hasPassword: true, archive: partial,
      excludeList: list, itemNames: ["-report"])
    #expect(args.firstIndex(of: "--")! < args.firstIndex(of: "-report")!)
    #expect(args.last == "-report")
  }

  @Test func sevenZipTest_args() {
    // No -p: on `t`, a bare -p means an empty password instead of a prompt
    #expect(
      CommandBuilder.sevenZipTest(archive: partial)
        == ["t", "-bb1", "-bsp0", "-spd", "--", "/x/p.7z.partial"])
  }

  @Test func excludeListContents() {
    #expect(CommandBuilder.excludeListContents(["._a.txt", "._b"]) == ".DS_Store\n._a.txt\n._b\n")
  }

  @Test func tar_args() {
    #expect(
      CommandBuilder.tarCreate(itemNames: ["p"])
        == ["-c", "-f", "-", "--exclude", ".DS_Store", "--exclude", "._*", "--", "p"])
    #expect(CommandBuilder.tarEnvironment == ["COPYFILE_DISABLE": "1"])
    #expect(CommandBuilder.tarCreate(itemNames: ["@notes"]).last == "./@notes")
  }

  @Test func zstd_levels() {
    let out = URL(filePath: "/x/p.tar.zst.partial")
    #expect(
      CommandBuilder.zstdCompress(level: .fast, output: out)
        == ["-1", "-T0", "-q", "-o", "/x/p.tar.zst.partial"])
    #expect(CommandBuilder.zstdCompress(level: .normal, output: out).first == "-3")
    #expect(CommandBuilder.zstdCompress(level: .maximum, output: out).first == "-19")
    #expect(CommandBuilder.zstdTest(archive: out) == ["-t", "-q", "--", "/x/p.tar.zst.partial"])
  }

  @Test func locate_prefersHomebrew() {
    let url = ToolLocator.locate(.sevenZip, isExecutable: { _ in true })
    #expect(url?.path == "/opt/homebrew/bin/7zz")
    let zstd = ToolLocator.locate(.zstd, isExecutable: { $0 == "/usr/local/bin/zstd" })
    #expect(zstd?.path == "/usr/local/bin/zstd")
  }

  @Test func locate_returnsNilWhenMissing() {
    #expect(ToolLocator.locate(.sevenZip, isExecutable: { _ in false }) == nil)
  }
}
