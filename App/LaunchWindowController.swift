import AppKit
import FinderSync
import SwiftUI

@MainActor
final class LaunchWindowController {
  private let window: NSWindow

  init(onDrop: @escaping ([URL]) -> Void) {
    let hosting = NSHostingController(rootView: LaunchView(onDrop: onDrop))
    hosting.sizingOptions = .preferredContentSize
    window = NSWindow(contentViewController: hosting)
    window.title = "PassArc"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
  }
}

private struct LaunchView: View {
  let onDrop: ([URL]) -> Void
  @State private var isTargeted = false

  var body: some View {
    VStack(spacing: 12) {
      dropZone
      if !FIFinderSyncController.isExtensionEnabled {
        Button("Enable Finder Extension…") {
          FIFinderSyncController.showExtensionManagementInterface()
        }
      }
    }
    .padding(20)
  }

  private var dropZone: some View {
    VStack(spacing: 12) {
      Image(systemName: "archivebox")
        .font(.system(size: 32))
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        .accessibilityHidden(true)
      Text("Drop files or folders here")
        .font(.headline)
    }
    .frame(width: 320, height: 150)
    .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary, style: StrokeStyle(dash: [5, 4]))
    }
    .clipShape(.rect(cornerRadius: 12))
    .contentShape(.rect)
    .dropDestination(for: URL.self) { urls, _ in
      let items = urls.filter(\.isFileURL)
      guard !items.isEmpty else { return false }
      onDrop(items)
      return true
    } isTargeted: {
      isTargeted = $0
    }
  }
}
