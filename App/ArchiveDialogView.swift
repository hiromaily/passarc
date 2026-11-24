import AppKit
import PassArcCore
import SwiftUI
import UniformTypeIdentifiers

struct ArchiveDialogView: View {
  @Bindable var model: ArchiveDialogModel
  @State private var showHelp = false
  @State private var showRecipientHelp = false
  @State private var showRecipientFile = false
  @State private var confirmKeyPairCreation = false
  private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
      switch model.phase {
      case .editing: editor
      case .running(let phase): running(phase)
      case .completed(let outputs): completed(outputs)
      case .failed(let message, let saved): failed(message, saved: saved)
      }
    }
    .padding(20)
    .frame(minWidth: 380, maxWidth: 480)
    .onChange(of: model.usesPublicKeys, initial: true) {
      model.loadDefaultRecipientIfNeeded()
    }
    .alert("Create an age key pair?", isPresented: $confirmKeyPairCreation) {
      Button("Create Key Pair") { Task { await model.createKeyPair() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("PassArc will save your keys in ~/\(AgeKeyPair.directoryPath) and add the public key to Recipients. Store the private key securely and keep a backup. You need it to open archives encrypted to your public key.")
    }
    .fileImporter(isPresented: $showRecipientFile, allowedContentTypes: [.item]) { result in
      guard case .success(let url) = result else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      model.importRecipients(from: url)
    }
  }

  private var title: String {
    if case .completed = model.phase { return "Compression complete" }
    return model.title
  }

  // MARK: - Input

  private var editor: some View {
    VStack(alignment: .leading, spacing: 14) {
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
        GridRow(alignment: .firstTextBaseline) {
          label("Format")
          VStack(alignment: .leading, spacing: 6) {
            ForEach(ArchiveFormat.allCases, id: \.self) { f in
              if f == .tarZst {
                Divider()
                  .frame(width: 100)
                  .accessibilityHidden(true)
              }
              RadioButton(
                title: f.displayName, isOn: model.state.format == f,
                isEnabled: model.state.isFormatEnabled(f)
              ) { model.state.format = f }
                // SwiftUI overrides NSButton.isEnabled, so disable it on the SwiftUI side too
                .disabled(!model.state.isFormatEnabled(f))
            }
          }
          .fixedSize()
        }
        if model.state.usePassword, let note = model.state.format.passwordCompatibilityNote {
          GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            Text(note)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(width: 250, alignment: .leading)
          }
        }
        GridRow(alignment: .firstTextBaseline) {
          label("Compression")
          Picker("Compression", selection: $model.state.level) {
            ForEach(CompressionLevel.allCases, id: \.self) { l in
              Text(l.displayName).tag(l)
            }
          }
          .pickerStyle(.radioGroup)
          .horizontalRadioGroupLayout()
          .labelsHidden()
          .fixedSize() // shrinking it truncates "Normal" and "Maximum"
        }
        GridRow {
          Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
          Toggle(
            model.state.format == .tarZstAge ? "Encrypt archive" : "Protect with a password",
            isOn: Binding(
              get: { model.state.usePassword },
              set: { model.state.setUsePassword($0) }))
        }
        if model.state.format == .tarZstAge && model.state.usePassword {
          GridRow(alignment: .firstTextBaseline) {
            label("Encryption")
            Picker("Encryption", selection: $model.useAgeRecipients) {
              Text("Passphrase").tag(false)
              Text("Public keys").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
          }
        }
        if model.usesPublicKeys {
          GridRow(alignment: .top) {
            label("Recipients")
            VStack(alignment: .leading, spacing: 6) {
              TextEditor(text: $model.ageRecipientText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 76)
                .border(.quaternary)
                .accessibilityLabel("Recipient public keys")
              Text("Enter one age or SSH public key per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack {
                Button("Import Recipient File…") { showRecipientFile = true }
                  .disabled(model.isCreatingKeyPair)
                HelpLink { showRecipientHelp = true }
                  .accessibilityLabel("Help with recipient public keys")
                  .popover(isPresented: $showRecipientHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                      Text("Recipient public keys").font(.headline)
                      Text("PassArc fills the empty list from ~/\(AgeKeyPair.directoryPath)/passarc-recipient.txt when you first select Public keys, if the file is available.")
                      Text("Each listed recipient can open the archive with their matching private key. Edit the list to choose who can open it.")
                      Text("To import from a hidden folder, press Command-Shift-G in the file picker and enter the folder path.")
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(width: 320, alignment: .leading)
                  }
              }
              if model.isCreatingKeyPair {
                ProgressView("Creating key pair…").controlSize(.small)
              } else if model.canCreateKeyPair {
                Button("Create Key Pair…") { confirmKeyPairCreation = true }
              } else if let message = model.incompleteKeyPairMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
              }
              if let message = model.recipientFileMessage {
                Text(message).font(.caption).foregroundStyle(.red)
              }
              if let message = model.recipientValidationMessage {
                Text(message).font(.caption).foregroundStyle(.red)
              }
            }
          }
        } else if model.state.usePassword {
          GridRow(alignment: .firstTextBaseline) {
            label("Password")
            SecureInputField(
              text: $model.state.password, onLeave: { model.state.didLeavePasswordField() })
          }
          GridRow(alignment: .firstTextBaseline) {
            label("Verify")
            SecureInputField(
              text: $model.state.confirmation,
              onLeave: { model.state.didLeaveConfirmationField() },
              onReturn: { model.submit() },
              keepFocus: { model.state.isMismatchShown })
          }
          GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            HStack {
              Button("Generate Password") { model.generatePassword() }
              Button("Copy Password") { model.copyPassword() }
            }
            .fixedSize()
          }
          if let message = model.state.passwordMessage {
            GridRow {
              Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
              Text(message).font(.caption).foregroundStyle(.red)
            }
          }
        }
      }
      if model.canCompressSeparately {
        Toggle(
          model.items.count == 1
            ? "Create a separate archive for each immediate subfolder"
            : "Create a separate archive for each folder",
          isOn: $model.compressSeparately)
      }
      HStack {
        HelpLink { showHelp = true }
          .popover(isPresented: $showHelp, arrowEdge: .bottom) { ArchiveHelpView() }
        if let version {
          Text("Version \(version)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel") { model.close() }
          .keyboardShortcut(.cancelAction)
        Button("Compress") { model.submit() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canSubmit)
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text).gridColumnAlignment(.trailing)
  }

  // MARK: - Running

  private func running(_ phase: JobPhase) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if let folder = model.currentFolder {
        Text(folder)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      switch phase {
      case .compressing(let fraction?):
        Text("Compressing…")
        ProgressView(value: fraction)
      case .compressing(nil):
        Text("Compressing…")
        ProgressView().progressViewStyle(.linear)
      case .verifying:
        Text("Verifying…")
        ProgressView().progressViewStyle(.linear)
      }
      HStack {
        Spacer()
        Button("Stop") { model.cancelIfRunning() }
          .keyboardShortcut(.cancelAction)
      }
    }
  }

  // MARK: - Results

  private func completed(_ outputs: [URL]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if outputs.count == 1, let output = outputs.first {
        Text(output.lastPathComponent)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(output.path)
      } else {
        Text("\(outputs.count) archives saved.")
      }
      resultActions(outputs, closeTitle: "Done")
    }
  }

  private func failed(_ message: String, saved: [URL]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ScrollView {
        Text(message)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 200)
      resultActions(saved, closeTitle: "Close")
    }
  }

  private func resultActions(_ outputs: [URL], closeTitle: String) -> some View {
    HStack {
      if !outputs.isEmpty {
        ShareLink(items: outputs) { Text("Share") }
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
      }
      Spacer()
      Button(closeTitle) { model.close() }
        .keyboardShortcut(.defaultAction)
        .keyboardShortcut(.cancelAction)
    }
  }
}

extension ArchiveFormat {
  fileprivate var passwordCompatibilityNote: String? {
    switch self {
    case .sevenZip:
      "AES-256 also encrypts file names. Recipients may need a compatible app to open this archive."
    case .zip:
      "Recipients may need an app that supports AES-256 encrypted ZIP archives."
    case .tarZst:
      nil
    case .tarZstAge:
      "age encrypts the entire archive, including file names. Recipients need an age-compatible tool and Zstandard."
    }
  }

  var displayName: String {
    self == .zip ? "ZIP" : fileExtension
  }
}

extension CompressionLevel {
  var displayName: String {
    switch self {
    case .fast: "Fast"
    case .normal: "Normal"
    case .maximum: "Maximum"
    }
  }
}

/// Shown by the ? button: explains that Archive Utility cannot open these archives
struct ArchiveHelpView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Opening password-protected archives").font(.headline)
      Text(
        "Password-protected 7z and ZIP archives are encrypted with AES-256. macOS Archive Utility cannot open them."
      )
      Text("To open them, right-click the archive in Finder and choose Extract with PassArc.")
      Text("With 7z, file names are encrypted too, so nothing is visible without the password.")
      Text("tar.zst does not support passwords.")
      Text("tar.zst.age encrypts contents and file names with a passphrase. Install age and Zstandard to open it in PassArc.")
    }
    .font(.callout)
    .fixedSize(horizontal: false, vertical: true)
    .padding(16)
    .frame(width: 320, alignment: .leading)
  }
}
