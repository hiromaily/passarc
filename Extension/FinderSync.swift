import AppKit
import FinderSync
import PassArcCore

/// Adds "Archive with Password" to the top level of the Finder context menu and hands the
/// selection to the app with passarc://archive?path=... (the sandboxed extension does not compress).
final class FinderSync: FIFinderSync {
  override init() {
    super.init()
    FIFinderSyncController.default().directoryURLs = [URL(filePath: "/")]
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    guard menuKind == .contextualMenuForItems else { return nil }
    let menu = NSMenu(title: "")
    menu.addItem(withTitle: "Archive with Password", action: #selector(archive(_:)), keyEquivalent: "")
    return menu
  }

  @objc func archive(_ sender: AnyObject?) {
    guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
      return
    }
    NSWorkspace.shared.open(ArchiveURL.make(items: items))
  }
}
