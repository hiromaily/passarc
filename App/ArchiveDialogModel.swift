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
  private(set) var phase: Phase = .editing
  private(set) var currentFolder: String?
  var close: () -> Void = {}
  var finishEditing: () -> Bool = { true }

  private let notifier: Notifier
  private let settings = SettingsStore()
  private var job: ArchiveJob?
  private var stopRequested = false

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

  func generatePassword() {
    guard phase == .editing, state.usePassword, finishEditing() else { return }

    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
    var random = SystemRandomNumberGenerator()
    let bytes = (0..<24).map { _ in alphabet[Int.random(in: alphabet.indices, using: &random)] }
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
    guard state.canSubmit, phase == .editing else { return }
    settings.save(state)
    let separately = canCompressSeparately && compressSeparately
    let format = state.format
    let level = state.level
    let password = state.usePassword ? state.password : nil
    state.password = ""
    state.confirmation = ""

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
            items: group, format: format, level: level, password: password))
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
