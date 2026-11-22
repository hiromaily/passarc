import Foundation

public enum ArchiveFormat: String, CaseIterable, Sendable, Codable {
  case sevenZip, zip, tarZstAge, tarZst

  enum Payload {
    case sevenZip, tarZst

    var tool: Tool {
      switch self {
      case .sevenZip: .sevenZip
      case .tarZst: .zstd
      }
    }
  }

  enum Encryption {
    case sevenZipPassword, none, age

    var passwordRules: (supported: Bool, required: Bool, maximumBytes: Int?) {
      switch self {
      case .sevenZipPassword: (true, false, nil)
      case .none: (false, false, nil)
      case .age: (true, true, AgeCommand.maximumPassphraseBytes)
      }
    }
  }

  private var configuration: (fileExtension: String, payload: Payload, encryption: Encryption) {
    switch self {
    case .sevenZip: ("7z", .sevenZip, .sevenZipPassword)
    case .zip: ("zip", .sevenZip, .sevenZipPassword)
    case .tarZst: ("tar.zst", .tarZst, .none)
    case .tarZstAge: ("tar.zst.age", .tarZst, .age)
    }
  }

  public var fileExtension: String { configuration.fileExtension }
  var payload: Payload { configuration.payload }
  var encryption: Encryption { configuration.encryption }

  public var supportsPassword: Bool { encryption.passwordRules.supported }
  public var requiresPassword: Bool { encryption.passwordRules.required }
  var maximumPasswordBytes: Int? { encryption.passwordRules.maximumBytes }
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
