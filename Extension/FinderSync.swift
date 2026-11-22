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
    if let items = FIFinderSyncController.default().selectedItemURLs(), archiveToExtract(items) != nil {
      menu.addItem(withTitle: "Extract with PassArc", action: #selector(extract(_:)), keyEquivalent: "")
    }
    return menu
  }

  @objc func archive(_ sender: AnyObject?) {
    guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
      return
    }
    NSWorkspace.shared.open(ArchiveURL.make(items: items))
  }

  @objc func extract(_ sender: AnyObject?) {
    guard let items = FIFinderSyncController.default().selectedItemURLs(),
          let archive = archiveToExtract(items)
    else { return }
    NSWorkspace.shared.open(ArchiveURL.makeExtraction(item: archive))
  }

  private func archiveToExtract(_ items: [URL]) -> URL? {
    guard items.count == 1, let item = items.first, ExtractionJob.format(of: item) != nil,
          (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else { return nil }
    return item
  }
}
