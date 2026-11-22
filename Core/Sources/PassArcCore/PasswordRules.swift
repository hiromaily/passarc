public enum PasswordProblem: Equatable, Sendable {
  case empty, mismatch, nonASCII, tooLong

  /// Text shown under the fields (DialogState decides when)
  public var message: String {
    switch self {
    case .empty: "Enter a password."
    case .mismatch: "The passwords don’t match."
    case .nonASCII: "Use only ASCII letters, numbers, and symbols."
    case .tooLong: "Use at most 1023 characters for tar.zst.age."
    }
  }
}

public enum PasswordRules {
  public static func check(
    _ password: String, confirmation: String, format: ArchiveFormat? = nil
  ) -> PasswordProblem? {
    if password.isEmpty { return .empty }
    let printableASCII = password.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    if !printableASCII { return .nonASCII }
    if let limit = format?.maximumPasswordBytes, password.utf8.count > limit { return .tooLong }
    if password != confirmation { return .mismatch }
    return nil
  }
}
