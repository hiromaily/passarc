import AppKit
import PassArcCore
import SwiftUI

@MainActor
final class ExtractionWindowController: NSObject, NSWindowDelegate, ObservableObject {
  @Published private(set) var isExtracting = true
  @Published private(set) var needsPassword = false
  @Published private(set) var canChooseIdentity = false
  @Published private(set) var identityNeedingPassphrase: URL?
  @Published private(set) var message: String?
  var onClose: (() -> Void)?
  let archive: URL

  private let notifier: Notifier
  private let window = NSWindow()
  private var task: Task<Void, Never>?

  init(archive: URL, notifier: Notifier) {
    self.archive = archive
    self.notifier = notifier
    super.init()
    let hosting = NSHostingController(rootView: ExtractionView(controller: self))
    hosting.sizingOptions = .preferredContentSize
    window.contentViewController = hosting
    window.title = "Extract Archive"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.delegate = self
  }

  func show() {
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
    extract()
  }

  func chooseIdentity() {
    let panel = NSOpenPanel()
    panel.title = "Choose age Identity"
    panel.prompt = "Extract"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let identity = panel.url else { return }
      self?.extract(ageIdentity: identity)
    }
  }

  func extract(password: String? = nil, ageIdentity: URL? = nil) {
    guard task == nil else { return }
    let ageIdentity = ageIdentity ?? identityNeedingPassphrase
    isExtracting = true
    message = nil
    task = Task { [weak self, archive] in
      do {
        let output = try await ExtractionJob(archive: archive, password: password, ageIdentity: ageIdentity).run()
        guard let self, !Task.isCancelled else { return }
        notifier.postCompleted(output, action: .extracted)
        notifier.playCompletionSound()
        NSWorkspace.shared.activateFileViewerSelecting([output])
        window.close()
      } catch {
        guard let self, !Task.isCancelled else { return }
        task = nil
        isExtracting = false
        identityNeedingPassphrase = nil
        switch error {
        case ExtractionError.ageIdentityPassphraseRequired, ExtractionError.incorrectAgeIdentityPassphrase,
             ExtractionError.invalidPassphrase where ageIdentity != nil:
          identityNeedingPassphrase = ageIdentity
          needsPassword = true
          canChooseIdentity = true
        case ExtractionError.passwordRequired, ExtractionError.incorrectPassword, ExtractionError.invalidPassphrase:
          needsPassword = true
          canChooseIdentity = ExtractionJob.format(of: archive) == .tarZstAge
        case ExtractionError.ageIdentityRequired:
          needsPassword = false
          canChooseIdentity = true
        case ExtractionError.invalidAgeIdentity, ExtractionError.ageIdentityDecryptionFailed:
          needsPassword = true
          canChooseIdentity = true
        default:
          needsPassword = false
          canChooseIdentity = false
        }
        if case ExtractionError.passwordRequired = error, canChooseIdentity {
          message = "Enter the archive passphrase or choose an age identity file."
        } else {
          message = error.localizedDescription
        }
      }
    }
  }

  func close() {
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    task?.cancel()
    task = nil
    window.contentViewController = nil
    onClose?()
  }
}

private struct ExtractionView: View {
  @ObservedObject var controller: ExtractionWindowController
  @State private var password = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(controller.archive.lastPathComponent)
        .font(.headline)
        .lineLimit(2)
        .truncationMode(.middle)
      if controller.isExtracting {
        ProgressView("Extracting…")
      }
      if let message = controller.message {
        Text(message).textSelection(.enabled)
      }
      if controller.needsPassword && !controller.isExtracting {
        SecureInputField(text: $password, onReturn: submit)
          .accessibilityLabel(controller.identityNeedingPassphrase == nil ? "Archive password" : "SSH private key passphrase")
          .frame(height: 24)
      }
      HStack {
        Spacer()
        Button(controller.isExtracting || controller.needsPassword || controller.canChooseIdentity ? "Cancel" : "Close") {
          controller.close()
        }
        .keyboardShortcut(.cancelAction)
        if controller.canChooseIdentity && !controller.isExtracting {
          Button("Choose Identity…", action: controller.chooseIdentity)
        }
        if controller.needsPassword && !controller.isExtracting {
          Button("Extract", action: submit)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(20)
    .frame(width: 360)
  }

  private func submit() {
    NSApp.keyWindow?.makeFirstResponder(nil)
    let entered = password
    password = ""
    controller.extract(password: entered)
  }
}
