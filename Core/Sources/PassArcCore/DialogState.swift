/// Dialog input and what it implies: enabled buttons, greyed-out formats, messages
public struct DialogState: Equatable, Sendable {
  public var format: ArchiveFormat
  public var level: CompressionLevel
  public private(set) var usePassword: Bool
  public var password: String
  public var confirmation: String
  /// Whether the field has lost focus at least once (decides when messages appear)
  public private(set) var passwordFieldLeft = false
  public private(set) var confirmationFieldLeft = false

  public init(
    format: ArchiveFormat, level: CompressionLevel, usePassword: Bool, password: String = "",
    confirmation: String = ""
  ) {
    self.format = format
    self.level = level
    self.usePassword = usePassword
    self.password = password
    self.confirmation = confirmation
  }

  /// Switches to a compatible format and clears the fields when protection is disabled.
  public mutating func setUsePassword(_ on: Bool) {
    usePassword = on
    if on {
      if !format.supportsPassword { format = .sevenZip }
    } else {
      if format.requiresPassword { format = .tarZst }
      password = ""
      confirmation = ""
      passwordFieldLeft = false
      confirmationFieldLeft = false
    }
  }

  public mutating func didLeavePasswordField() { passwordFieldLeft = true }
  public mutating func didLeaveConfirmationField() { confirmationFieldLeft = true }

  public func isFormatEnabled(_ f: ArchiveFormat) -> Bool {
    usePassword ? f.supportsPassword : !f.requiresPassword
  }

  private var problem: PasswordProblem? {
    usePassword ? PasswordRules.check(password, confirmation: confirmation, format: format) : nil
  }

  public var canSubmit: Bool { isFormatEnabled(format) && problem == nil }

  /// Empty and non-ASCII appear after leaving Password; a mismatch after leaving Verify
  public var passwordMessage: String? {
    switch problem {
    case .nonASCII where passwordFieldLeft: PasswordProblem.nonASCII.message
    case .empty where passwordFieldLeft: PasswordProblem.empty.message
    case .tooLong where passwordFieldLeft: PasswordProblem.tooLong.message
    case .mismatch where confirmationFieldLeft: PasswordProblem.mismatch.message
    default: nil
    }
  }

  /// Whether the mismatch message is shown (used to keep focus in Verify)
  public var isMismatchShown: Bool { confirmationFieldLeft && problem == .mismatch }
}
