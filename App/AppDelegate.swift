import AppKit
import FinderSync
import PassArcCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windows: Set<ArchiveWindowController> = []
  private var extractionWindows: Set<ExtractionWindowController> = []
  private let notifier = Notifier()

  static func main() {
    signal(SIGPIPE, SIG_IGN)  // a closed pipe to a child process must not kill the app
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // no Dock icon
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    notifier.start()
  }

  func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
    showFinderSetupIfNeeded()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows { _ = showFinderSetupIfNeeded() }
    return false
  }

  private func showFinderSetupIfNeeded() -> Bool {
    guard !FIFinderSyncController.isExtensionEnabled else { return false }
    let alert = NSAlert()
    alert.messageText = "Enable PassArc in Finder"
    alert.informativeText = "Open System Settings and turn on PassArcFinder. Then right-click a file or folder and choose Archive with Password."
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      FIFinderSyncController.showExtensionManagementInterface()
    }
    return true
  }

  /// Opens one window per Finder request.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if let archive = ArchiveURL.parseExtraction(url) {
        let controller = ExtractionWindowController(archive: archive, notifier: notifier)
        controller.onClose = { [weak self, weak controller] in
          if let controller { self?.extractionWindows.remove(controller) }
        }
        extractionWindows.insert(controller)
        controller.show()
        continue
      }
      guard let items = ArchiveURL.parse(url) else { continue }
      let controller = ArchiveWindowController(items: items, notifier: notifier)
      controller.onClose = { [weak self, weak controller] in
        if let controller { self?.windows.remove(controller) }
      }
      windows.insert(controller)
      controller.show()
    }
  }
}
