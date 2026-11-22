import Foundation

public struct AgeRecipients: Sendable {
  private let lines: [(number: Int, text: String)]

  public init(_ text: String) {
    lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .enumerated().compactMap { index, value in
        let line = value.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        return (index + 1, line)
      }
  }

  public var isEmpty: Bool { lines.isEmpty }

  func validatedKeys() throws -> [(line: Int, key: String)] {
    var keys: [(line: Int, key: String)] = []
    for (number, line) in lines {
      guard let key = AgeCommand.recipientKey(line) else {
        throw ArchiveError.invalidAgeRecipients("Line \(number): Enter a valid age, ssh-ed25519, or ssh-rsa public key.")
      }
      keys.append((number, key))
    }
    guard let firstKey = keys.first else {
      throw ArchiveError.invalidAgeRecipients("Enter at least one recipient public key.")
    }
    let isPostQuantum = firstKey.key.hasPrefix("age1pq1")
    if let mixed = keys.first(where: { $0.key.hasPrefix("age1pq1") != isPostQuantum }) {
      throw ArchiveError.invalidAgeRecipients(
        "Line \(mixed.line): Use either post-quantum age keys or classic age and SSH keys for all recipients.")
    }
    return keys
  }
}
