import AppKit
import PassArcCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windows: Set<ArchiveWindowController> = []
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

  /// Called for passarc://archive?path=...; one window per URL
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
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
