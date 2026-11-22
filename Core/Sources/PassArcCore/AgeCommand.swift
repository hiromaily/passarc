import Foundation

enum AgeCommand {
  // age reads in canonical mode, which needs room for the terminating newline.
  static let maximumPassphraseBytes = 1023

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
