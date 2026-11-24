import AppKit
import Observation
import PassArcCore

@MainActor
@Observable
final class ArchiveDialogModel {
  enum Phase: Equatable {
    case editing
    case running(JobPhase)
    case completed([URL])
    case failed(String, saved: [URL])
  }

  let items: [URL]
  let canCompressSeparately: Bool
  var compressSeparately = false
  var state: DialogState
  var useAgeRecipients = false
  var ageRecipientText = ""
  private(set) var recipientFileMessage: String?
  private(set) var recipientValidationMessage: String?
  private(set) var isCreatingKeyPair = false
  private(set) var phase: Phase = .editing
  private(set) var currentFolder: String?
  var close: () -> Void = {}
  var finishEditing: () -> Bool = { true }

  private let notifier: Notifier
  private let settings = SettingsStore()
  private var job: ArchiveJob?
  private var stopRequested = false
  private var checkedDefaultRecipient = false

  private let keyPair = AgeKeyPair(directory: FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(AgeKeyPair.directoryPath, isDirectory: true))

  var canCreateKeyPair: Bool { !keyPair.hasIdentity && !keyPair.hasRecipient }

  var incompleteKeyPairMessage: String? {
    if keyPair.hasIdentity && !keyPair.hasRecipient {
      return "Only the private key exists in the default folder. Restore the public key or export it with age-keygen -y."
    }
    if keyPair.hasRecipient && !keyPair.hasIdentity {
      return "Only the public key exists in the default folder. Restore the matching private key from your backup."
    }
    return nil
  }

  init(items: [URL], notifier: Notifier) {
    self.items = items
    canCompressSeparately = !items.isEmpty && items.allSatisfy { item in
      let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      return values?.isDirectory == true && values?.isSymbolicLink == false
    }
    self.notifier = notifier
    state = settings.load()
  }

  var title: String {
    items.count == 1 ? "📁 Compress “\(items[0].lastPathComponent)”" : "📁 Compress \(items.count) items"
  }

  var usesPublicKeys: Bool { state.format == .tarZstAge && state.usePassword && useAgeRecipients }

  private var ageRecipients: AgeRecipients { AgeRecipients(ageRecipientText) }

  var canSubmit: Bool {
    !isCreatingKeyPair && (usesPublicKeys ? !ageRecipients.isEmpty : state.canSubmit)
  }

  func loadDefaultRecipientIfNeeded() {
    guard usesPublicKeys, !checkedDefaultRecipient else { return }
    checkedDefaultRecipient = true
    guard ageRecipientText.isEmpty else { return }
    guard let text = try? readRecipients(from: keyPair.recipient), !AgeRecipients(text).isEmpty else { return }
    ageRecipientText = text
  }

  func createKeyPair() async {
    guard phase == .editing, usesPublicKeys, !isCreatingKeyPair else { return }
    isCreatingKeyPair = true
    recipientFileMessage = nil
    defer { isCreatingKeyPair = false }
    do {
      try await Task.detached { [keyPair] in try keyPair.create() }.value
      importRecipients(from: keyPair.recipient)
    } catch {
      recipientFileMessage = "Could not create keys. \(error.localizedDescription)"
    }
  }

  func importRecipients(from url: URL) {
    recipientFileMessage = nil
    do {
      let text = try readRecipients(from: url)
      if !ageRecipientText.isEmpty { ageRecipientText.append("\n") }
      ageRecipientText.append(text)
    } catch {
      recipientFileMessage = "Choose a UTF-8 text file containing recipient public keys (up to 64 KiB)."
    }
  }

  private func readRecipients(from url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let limit = 64 * 1024
    guard let data = try file.read(upToCount: limit + 1), data.count <= limit,
          let text = String(data: data, encoding: .utf8)
    else { throw CocoaError(.fileReadCorruptFile) }
    return text
  }

  func generatePassword() {
    guard phase == .editing, state.usePassword, finishEditing() else { return }

    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
    var random = SystemRandomNumberGenerator()
    let bytes = (0 ..< 24).map { _ in alphabet[Int.random(in: alphabet.indices, using: &random)] }
    let password = String(decoding: bytes, as: UTF8.self)
    state.password = password
    state.confirmation = password
  }

  func copyPassword() {
    guard phase == .editing, state.usePassword, finishEditing() else { return }
    state.didLeavePasswordField()
    state.didLeaveConfirmationField()
    guard state.canSubmit else { return }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(state.password, forType: .string)
  }

  func submit() {
    guard canSubmit, phase == .editing else { return }
    settings.save(state)
    let separately = canCompressSeparately && compressSeparately
    let format = state.format
    let level = state.level
    let protection: ArchiveProtection
    if usesPublicKeys {
      protection = .ageRecipients(ageRecipients)
    } else {
      protection = state.usePassword ? .password(state.password) : .none
    }
    state.password = ""
    state.confirmation = ""
    recipientValidationMessage = nil

    phase = .running(.compressing(nil))
    Task {
      var outputs: [URL] = []
      do {
        let groups: [[URL]]
        if separately && items.count == 1 {
          let subfolders = try FileInventory.immediateSubfolders(of: items[0])
          guard !subfolders.isEmpty else {
            phase = .failed("The selected folder contains no subfolders to compress.", saved: [])
            return
          }
          groups = subfolders.map { [$0] }
        } else if separately {
          // Archive ancestors before creating any archives of their selected descendants.
          groups = items.map { ($0, $0.resolvingSymlinksInPath().pathComponents.count) }
            .sorted { $0.1 < $1.1 }.map { [$0.0] }
        } else {
          groups = [items]
        }
        for (index, group) in groups.enumerated() {
          if stopRequested { throw ArchiveError.cancelled }
          if separately {
            currentFolder = "Folder \(index + 1) of \(groups.count) · \(group[0].lastPathComponent)"
          }
          let job = ArchiveJob(request: ArchiveRequest(
            items: group, format: format, level: level, protection: protection))
          self.job = job
          phase = .running(.compressing(nil))
          let output = try await job.run { progress in
            Task { @MainActor [weak self] in
              guard let self, self.job === job else { return }
              self.phase = .running(progress)
            }
          }
          outputs.append(output)
        }
        job = nil
        notifier.postArchivesCreated(outputs)
        phase = .completed(outputs)
        notifier.playCompletionSound()
      } catch ArchiveError.cancelled {
        job = nil
        notifier.postArchivesCreated(outputs)
        if outputs.isEmpty {
          close()
        } else {
          let saved = outputs.count == 1 ? "1 archive saved." : "\(outputs.count) archives saved."
          phase = .failed("Compression stopped.\n\n\(saved)", saved: outputs)
        }
      } catch {
        job = nil
        if case ArchiveError.invalidAgeRecipients(let detail) = error, outputs.isEmpty {
          recipientValidationMessage = detail
          currentFolder = nil
          phase = .editing
          return
        }
        let detail = (error as? ArchiveError)?.message ?? error.localizedDescription
        guard let currentFolder else {
          phase = .failed(detail, saved: outputs)
          return
        }
        notifier.postArchivesCreated(outputs)
        let saved = outputs.count == 1 ? "1 archive saved." : "\(outputs.count) archives saved."
        phase = .failed("\(currentFolder)\n\(detail)\n\n\(saved)", saved: outputs)
      }
    }
  }

  func cancelIfRunning() {
    guard case .running = phase else { return }
    stopRequested = true
    job?.cancel()
  }
}
