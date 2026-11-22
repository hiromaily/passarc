import Foundation

/// Arguments for each tool. No function takes a password, so it can never end up in argv.
/// PTYRunner gives the password by answering 7zz's prompt.
public enum CommandBuilder {
  static let excludedNames = [".DS_Store", "._*"]

  /// itemNames are relative to the working directory (the items' shared parent)
  public static func sevenZipCreate(
    format: ArchiveFormat, level: CompressionLevel, hasPassword: Bool, archive: URL,
    excludeList: URL, itemNames: [String]
  ) -> [String] {
    precondition(format.payload == .sevenZip, "This format is not created with 7zz")
    var args = [
      "a", format == .sevenZip ? "-t7z" : "-tzip", "-mx=\(mx(level))", "-mmt=on", "-snl", "-bsp1",
      "-spd", // treat * and ? in names literally
    ]
    // -spd also disables wildcards in excludes, so pass literal names in a list file
    args += ["-scsUTF-8", "-xr@\(excludeList.path)"]
    if hasPassword {
      args += format == .sevenZip ? ["-mhe=on"] : ["-mem=AES256"]
      args.append("-p") // no value: 7zz prompts on the terminal
    }
    return args + ["--", archive.path] + itemNames
  }

  /// Contents of the 7zz exclude list: .DS_Store and the ._* names found (excluded at any depth)
  public static func excludeListContents(_ names: Set<String>) -> String {
    (Set([".DS_Store"]).union(names)).sorted().map { $0 + "\n" }.joined()
  }

  /// -bb1 prints one "T <name>" line per tested item; with a single file there is no "Files: N" line
  public static func sevenZipTest(archive: URL) -> [String] {
    ["t", "-bb1", "-bsp0", "-spd", "--", archive.path]
  }

  public static func tarCreate(itemNames: [String]) -> [String] {
    // bsdtar reads "@name" as "add the entries of archive name" (even after "--"), so add "./"
    ["-c", "-f", "-"] + excludedNames.flatMap { ["--exclude", $0] } + ["--"]
      + itemNames.map { $0.hasPrefix("@") ? "./" + $0 : $0 }
  }

  public static let tarEnvironment = ["COPYFILE_DISABLE": "1"]

  public static func zstdCompress(level: CompressionLevel, output: URL) -> [String] {
    let l =
      switch level {
      case .fast: "-1"
      case .normal: "-3"
      case .maximum: "-19"
      }
    return [l, "-T0", "-q", "-o", output.path]
  }

  public static func zstdTest(archive: URL) -> [String] {
    ["-t", "-q", "--", archive.path]
  }

  private static func mx(_ level: CompressionLevel) -> Int {
    switch level {
    case .fast: 1
    case .normal: 5
    case .maximum: 9
    }
  }
}
