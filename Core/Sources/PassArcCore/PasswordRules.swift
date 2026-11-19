public enum PasswordProblem: Equatable, Sendable {
  case empty, mismatch, nonASCII

  /// Text shown under the fields (DialogState decides when)
  public var message: String {
    switch self {
    case .empty: "Enter a password."
    case .mismatch: "The passwords don’t match."
    case .nonASCII: "Use only ASCII letters, numbers, and symbols."
    }
  }
}

public enum PasswordRules {
  public static func check(_ password: String, confirmation: String) -> PasswordProblem? {
    if password.isEmpty { return .empty }
    let printableASCII = password.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    if !printableASCII { return .nonASCII }
    if password != confirmation { return .mismatch }
    return nil
  }
}
