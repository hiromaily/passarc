import AppKit
import Observation
import PassArcCore

@MainActor
@Observable
final class ArchiveDialogModel {
  enum Phase: Equatable {
    case editing
    case running(JobPhase)
    case failed(String)
  }

  let items: [URL]
  var state: DialogState
  private(set) var phase: Phase = .editing
  var close: () -> Void = {}
  var finishEditing: () -> Bool = { true }

  private let notifier: Notifier
  private let settings = SettingsStore()
  private var job: ArchiveJob?

  init(items: [URL], notifier: Notifier) {
    self.items = items
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
    let request = ArchiveRequest(
      items: items, format: state.format, level: state.level,
      password: state.usePassword ? state.password : nil)
    // Clear the password from the model once the job has it
    state.password = ""
    state.confirmation = ""

    let job = ArchiveJob(request: request)
    self.job = job
    phase = .running(.compressing(nil))
    Task {
      do {
        let output = try await job.run(progress: { p in
          Task { @MainActor [weak self] in
            if case .running = self?.phase { self?.phase = .running(p) }
          }
        })
        self.job = nil
        notifier.postCompleted(output)
        close()
      } catch ArchiveError.cancelled {
        self.job = nil
        close()
      } catch let error as ArchiveError {
        self.job = nil
        phase = .failed(error.message)
      } catch {
        self.job = nil
        phase = .failed(error.localizedDescription)
      }
    }
  }

  func cancelIfRunning() {
    job?.cancel()
  }
}
