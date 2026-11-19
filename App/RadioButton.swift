import AppKit
import SwiftUI

/// One native radio button (NSButton). SwiftUI's radio-group Picker ignores .disabled on
/// single options, so tar.zst could not be greyed out.
struct RadioButton: NSViewRepresentable {
  let title: String
  let isOn: Bool
  let isEnabled: Bool
  let action: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(action) }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      radioButtonWithTitle: title, target: context.coordinator,
      action: #selector(Coordinator.clicked))
    button.setContentHuggingPriority(.required, for: .horizontal)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
    button.title = title
    button.state = isOn ? .on : .off
    button.isEnabled = isEnabled
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func clicked() { action() }
  }
}
