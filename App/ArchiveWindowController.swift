import AppKit
import SwiftUI

@MainActor
final class ArchiveWindowController: NSObject, NSWindowDelegate {
  var onClose: (() -> Void)?
  private let model: ArchiveDialogModel
  private let window: NSWindow

  init(items: [URL], notifier: Notifier) {
    model = ArchiveDialogModel(items: items, notifier: notifier)
    let hosting = NSHostingController(rootView: ArchiveDialogView(model: model))
    hosting.sizingOptions = .preferredContentSize
    window = NSWindow(contentViewController: hosting)
    window.title = "PassArc"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    super.init()
    window.delegate = self
    model.close = { [weak self] in self?.window.close() }
    model.finishEditing = { [weak self] in self?.window.makeFirstResponder(nil) ?? false }
  }

  func show() {
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    model.cancelIfRunning()
    onClose?()
  }
}
