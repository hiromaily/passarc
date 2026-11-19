// Development tool: renders the dialog to PNG (works without Screen Recording permission).
// Usage: scripts/snapshot.sh <output dir>
import AppKit
import PassArcCore
import SwiftUI

@MainActor
func render(_ view: some View, to url: URL) {
  let hosting = NSHostingView(rootView: view)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered,
    defer: false)
  window.contentView = hosting
  hosting.layoutSubtreeIfNeeded()
  window.setContentSize(hosting.fittingSize)
  hosting.layoutSubtreeIfNeeded()
  RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
  hosting.cacheDisplay(in: hosting.bounds, to: rep)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print("wrote \(url.path) \(hosting.bounds.size)")
}

@MainActor
func main() {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.prohibited)
  let out = URL(filePath: CommandLine.arguments[1])
  let items = [URL(filePath: "/tmp/projects-2026")]

  let on = ArchiveDialogModel(items: items, notifier: Notifier())
  on.state = DialogState(format: .sevenZip, level: .normal, usePassword: true)
  render(ArchiveDialogView(model: on), to: out.appending(path: "dialog-password.png"))

  let mismatch = ArchiveDialogModel(items: items, notifier: Notifier())
  var s = DialogState(format: .sevenZip, level: .normal, usePassword: true, password: "abc", confirmation: "ab")
  s.didLeavePasswordField(); s.didLeaveConfirmationField()
  mismatch.state = s
  render(ArchiveDialogView(model: mismatch), to: out.appending(path: "dialog-mismatch.png"))

  let off = ArchiveDialogModel(items: items, notifier: Notifier())
  off.state = DialogState(format: .tarZst, level: .fast, usePassword: false)
  render(ArchiveDialogView(model: off), to: out.appending(path: "dialog-nopassword.png"))

  render(ArchiveHelpView(), to: out.appending(path: "help.png"))
}

MainActor.assumeIsolated { main() }
