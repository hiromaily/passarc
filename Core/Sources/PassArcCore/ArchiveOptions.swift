import Foundation

public enum ArchiveFormat: String, CaseIterable, Sendable, Codable {
  case sevenZip, zip, tarZst

  public var fileExtension: String {
    switch self {
    case .sevenZip: "7z"
    case .zip: "zip"
    case .tarZst: "tar.zst"
    }
  }

  /// zstd has no password support
  public var supportsPassword: Bool { self != .tarZst }
}

public enum CompressionLevel: String, CaseIterable, Sendable, Codable {
  case fast, normal, maximum
}

public struct ArchiveRequest: Sendable {
  public var items: [URL]
  public var format: ArchiveFormat
  public var level: CompressionLevel
  public var password: String?

  public init(items: [URL], format: ArchiveFormat, level: CompressionLevel, password: String?) {
    self.items = items
    self.format = format
    self.level = level
    self.password = password
  }
}
