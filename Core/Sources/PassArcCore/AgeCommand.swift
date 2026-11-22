import Foundation

enum AgeCommand {
  // age reads in canonical mode, which needs room for the terminating newline.
  static let maximumPassphraseBytes = 1023

  static func identityRunner(
    executable: URL, input: URL, output: URL, identity: URL, passphrase: String?
  ) -> PTYRunner {
    PTYRunner(
      executable: executable,
      arguments: ["--decrypt", "--identity", identity.path, "--output", output.path, "--", input.path],
      currentDirectory: output.deletingLastPathComponent(), password: passphrase ?? "",
      prompt: { text in
        let last = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return isIdentityPassphrasePrompt(last)
      })
  }

  static func isIdentityPassphrasePrompt(_ line: Substring) -> Bool {
    let prompt = line.trimmingCharacters(in: .whitespaces)
    return prompt.hasPrefix("Enter passphrase for \"") && prompt.hasSuffix("\":")
  }

  static func recipientRunner(executable: URL, input: URL, output: URL, recipients: [String]) -> PTYRunner {
    PTYRunner(
      executable: executable,
      arguments: recipients.flatMap { ["--recipient", $0] } + ["--output", output.path, "--", input.path],
      currentDirectory: output.deletingLastPathComponent(), password: nil, useTerminal: false)
  }

  static func recipientKey(_ line: String) -> String? {
    if line.hasPrefix("age1") {
      let encoded = line.dropFirst(line.hasPrefix("age1pq1") ? "age1pq1".count : "age1".count)
      let alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
      return !encoded.isEmpty && encoded.allSatisfy(alphabet.contains) ? line : nil
    }
    guard !line.contains(where: \.isNewline) else { return nil }
    let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
    guard fields.count >= 2, fields[0] == "ssh-ed25519" || fields[0] == "ssh-rsa",
          Data(base64Encoded: String(fields[1])) != nil
    else { return nil }
    return fields.prefix(2).joined(separator: " ")
  }

  static func isSupportedIdentityFile(_ identity: URL) throws -> Bool {
    guard identity.isFileURL,
          try identity.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
    else { return false }
    let file = try FileHandle(forReadingFrom: identity)
    defer { try? file.close() }
    // Bound reads of arbitrary files selected in the open panel.
    let limit = 64 * 1024
    guard let data = try file.read(upToCount: limit + 1), data.count <= limit,
          let text = String(data: data, encoding: .utf8)
    else { return false }
    let lines = text.split(whereSeparator: \.isNewline)
    for type in ["OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "PRIVATE KEY"] {
      if lines.first == "-----BEGIN \(type)-----", lines.last == "-----END \(type)-----" {
        return true
      }
    }
    let keys = lines.filter { !$0.hasPrefix("#") }
    return !keys.isEmpty && keys.allSatisfy { $0.hasPrefix("AGE-SECRET-KEY-1") || $0.hasPrefix("AGE-SECRET-KEY-PQ-1") }
  }

  static func runner(
    executable: URL, decrypt: Bool, input: URL, output: URL, password: String
  ) -> PTYRunner {
    PTYRunner(
      executable: executable,
      arguments: [decrypt ? "--decrypt" : "--passphrase", "--output", output.path, "--", input.path],
      currentDirectory: output.deletingLastPathComponent(), password: password,
      prompt: { text in
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        let prompt = line.trimmingCharacters(in: .whitespaces)
        return prompt.hasSuffix("Enter passphrase:")
          || prompt.hasSuffix("Enter passphrase (leave empty to autogenerate a secure one):")
          || prompt.hasSuffix("Confirm passphrase:")
      })
  }
}
