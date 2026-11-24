import AppKit
import PassArcCore
import SwiftUI

@MainActor
final class ExtractionWindowController: NSObject, NSWindowDelegate, ObservableObject {
  @Published private(set) var isExtracting = true
  @Published private(set) var needsPassword = false
  @Published private(set) var canChooseIdentity = false
  @Published private(set) var defaultIdentity: URL?
  @Published private(set) var chosenIdentity: URL?
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
    panel.prompt = "Choose"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let identity = panel.url else { return }
      chosenIdentity = identity
      identityNeedingPassphrase = nil
      message = nil
    }
  }

  func extract(password: String? = nil, ageIdentity: URL? = nil) {
    guard task == nil else { return }
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
        if !canChooseIdentity || identityNeedingPassphrase != nil || (ageIdentity != nil && ageIdentity == defaultIdentity) {
          defaultIdentity = nil
        } else if ageIdentity == nil, password == nil {
          let identity = AgeKeyPair.defaultLocation.identity
          if (try? identity.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
             FileManager.default.isReadableFile(atPath: identity.path) {
            defaultIdentity = identity
          }
        }
        switch error {
        case ExtractionError.passwordRequired where canChooseIdentity, ExtractionError.ageIdentityRequired:
          message = nil
        default:
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
  private enum Method {
    case identity, passphrase
  }

  @ObservedObject var controller: ExtractionWindowController
  @State private var password = ""
  @State private var chosenMethod: Method?
  @State private var showIdentityHelp = false

  private var identity: URL? {
    controller.identityNeedingPassphrase ?? controller.chosenIdentity ?? controller.defaultIdentity
  }

  private var method: Method {
    guard controller.canChooseIdentity else { return .passphrase }
    if !controller.needsPassword { return .identity }
    return chosenMethod ?? (identity == nil ? .passphrase : .identity)
  }

  private var showsPassword: Bool {
    method == .passphrase ? controller.needsPassword : controller.identityNeedingPassphrase != nil
  }

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
      if !controller.isExtracting {
        if controller.canChooseIdentity {
          credentialMethod
          if method == .identity { identityPicker }
        }
        if showsPassword {
          let label = method == .identity ? "SSH key passphrase" : "Archive passphrase"
          VStack(alignment: .leading, spacing: 5) {
            Text(label)
            SecureInputField(text: $password, onReturn: submit)
              .accessibilityLabel(label)
              .frame(height: 24)
          }
        }
      }
      HStack {
        Spacer()
        Button(controller.isExtracting || controller.needsPassword || controller.canChooseIdentity ? "Cancel" : "Close") {
          controller.close()
        }
        .keyboardShortcut(.cancelAction)
        if (controller.needsPassword || controller.canChooseIdentity) && !controller.isExtracting {
          Button("Extract", action: submit)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
      }
    }
    .padding(20)
    .frame(width: 380)
  }

  private var credentialMethod: some View {
    HStack {
      if controller.needsPassword {
        Picker("Unlock with", selection: Binding(
          get: { method },
          set: {
            chosenMethod = $0
            password = ""
          })) {
            Text("Identity file").tag(Method.identity)
            Text("Passphrase").tag(Method.passphrase)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
      } else {
        Text("Identity file")
        Spacer()
      }
      HelpLink { showIdentityHelp = true }
        .accessibilityLabel("Help with age identities")
        .popover(isPresented: $showIdentityHelp, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 10) {
            Text("Age identity files").font(.headline)
            Text("PassArc looks for ~/\(AgeKeyPair.directoryPath)/\(AgeKeyPair.identityName). A detected key appears under Identity file.")
            Text("To select a different private key from a hidden folder, press Command-Shift-G in the file picker and enter the folder path.")
          }
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
          .padding(16)
          .frame(width: 320, alignment: .leading)
        }
    }
  }

  private var identityPicker: some View {
    HStack {
      if let identity {
        Text(identity.lastPathComponent)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(identity.path)
      } else {
        Text("No identity selected").foregroundStyle(.secondary)
      }
      Spacer()
      Button(identity == nil ? "Choose…" : "Change…", action: controller.chooseIdentity)
        .accessibilityLabel("Choose identity file")
    }
  }

  private var canSubmit: Bool {
    !controller.isExtracting &&
      (method == .passphrase ? controller.needsPassword : identity != nil) &&
      (!showsPassword || !password.isEmpty)
  }

  private func submit() {
    guard canSubmit else { return }
    NSApp.keyWindow?.makeFirstResponder(nil)
    let entered = showsPassword ? password : nil
    password = ""
    controller.extract(password: entered, ageIdentity: method == .identity ? identity : nil)
  }
}
