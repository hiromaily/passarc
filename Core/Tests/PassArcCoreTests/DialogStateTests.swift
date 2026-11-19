import Testing

@testable import PassArcCore

@Suite struct DialogStateTests {
  private func state(
    format: ArchiveFormat = .sevenZip, usePassword: Bool = true, password: String = "",
    confirmation: String = ""
  ) -> DialogState {
    DialogState(
      format: format, level: .normal, usePassword: usePassword, password: password,
      confirmation: confirmation)
  }

  @Test func check_rejectsEmpty() {
    #expect(PasswordRules.check("", confirmation: "") == .empty)
  }

  @Test func check_rejectsMismatch() {
    #expect(PasswordRules.check("abc", confirmation: "abd") == .mismatch)
  }

  @Test func check_rejectsNonASCII() {
    #expect(PasswordRules.check("ぱすわーど", confirmation: "ぱすわーど") == .nonASCII)
    #expect(PasswordRules.check("abc１", confirmation: "abc１") == .nonASCII)
    #expect(PasswordRules.check("ぱ", confirmation: "x") == .nonASCII)  // checked before the match
  }

  @Test func check_acceptsSpaceAndSymbols() {
    #expect(PasswordRules.check("a b~!", confirmation: "a b~!") == nil)
  }

  @Test func messages() {
    #expect(PasswordProblem.empty.message == "Enter a password.")
    #expect(PasswordProblem.mismatch.message == "The passwords don’t match.")
    #expect(PasswordProblem.nonASCII.message == "Use only ASCII letters, numbers, and symbols.")
  }

  @Test func state_tarZstDisabledWithPassword() {
    #expect(state(usePassword: true).isFormatEnabled(.tarZst) == false)
    #expect(state(usePassword: false).isFormatEnabled(.tarZst))
    #expect(state(usePassword: true).isFormatEnabled(.zip))
  }

  @Test func state_turningPasswordOnSwitchesFromTarZst() {
    var s = state(format: .tarZst, usePassword: false)
    s.setUsePassword(true)
    #expect(s.format == .sevenZip)
    #expect(s.usePassword)
  }

  @Test func state_turningPasswordOffClearsFields() {
    var s = state(password: "a", confirmation: "a")
    s.setUsePassword(false)
    #expect(s.password == "")
    #expect(s.confirmation == "")
  }

  @Test func state_canSubmitWithoutPassword() {
    #expect(state(usePassword: false).canSubmit)
  }

  @Test func state_cannotSubmitUntilValid() {
    #expect(state(password: "a", confirmation: "b").canSubmit == false)
    #expect(state(password: "a", confirmation: "a").canSubmit)
    #expect(state().canSubmit == false)
  }

  @Test func message_mismatchWaitsUntilConfirmationFieldIsLeft() {
    var s = state(password: "abc", confirmation: "a")
    #expect(s.passwordMessage == nil)  // not shown while typing
    s.didLeaveConfirmationField()
    #expect(s.passwordMessage == "The passwords don’t match.")
    s.confirmation = "abc"  // after leaving, fixing it clears the message right away
    #expect(s.passwordMessage == nil)
  }

  @Test func message_emptyWaitsUntilPasswordFieldIsLeft() {
    var s = state()
    #expect(s.passwordMessage == nil)
    s.didLeavePasswordField()
    #expect(s.passwordMessage == "Enter a password.")
  }

  @Test func message_nonASCIIWaitsUntilPasswordFieldIsLeft() {
    var s = state(password: "ぱ")
    #expect(s.passwordMessage == nil)
    s.didLeavePasswordField()
    #expect(s.passwordMessage == "Use only ASCII letters, numbers, and symbols.")
  }

  @Test func message_resetsWhenPasswordTurnedOff() {
    var s = state(password: "a", confirmation: "b")
    s.didLeaveConfirmationField()
    s.setUsePassword(false)
    s.setUsePassword(true)
    s.password = "a"
    s.confirmation = "b"
    #expect(s.passwordMessage == nil)
  }

  @Test func mismatchShown_onlyAfterLeavingConfirmation() {
    var s = state(password: "hello", confirmation: "hell")
    #expect(s.isMismatchShown == false)
    s.didLeaveConfirmationField()
    #expect(s.isMismatchShown)
    s.confirmation = "hello"
    #expect(s.isMismatchShown == false)
  }
}
