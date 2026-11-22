import Foundation

public enum Tool: String, Sendable {
  case sevenZip = "7zz"
  case zstd
  case age

  /// The Homebrew package to suggest when the tool is missing
  public var brewPackage: String {
    switch self {
    case .sevenZip: "sevenzip"
    case .zstd: "zstd"
    case .age: "age"
    }
  }
}

public enum ToolLocator {
  public static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

  public static func locate(
    _ tool: Tool,
    isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) -> URL? {
    searchDirectories
      .map { "\($0)/\(tool.rawValue)" }
      .first(where: isExecutable)
      .map { URL(filePath: $0) }
  }
}
