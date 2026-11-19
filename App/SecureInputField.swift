import AppKit
import SwiftUI

/// A native password field (NSSecureTextField).
/// SwiftUI's SecureField writes the value back on every redraw, which made input-method text appear twice.
/// The value is passed to `text` only when the field loses focus (no per-keystroke validation).
struct SecureInputField: NSViewRepresentable {
  @Binding var text: String
  /// Called when the field loses focus (after `text` is updated)
  var onLeave: () -> Void = {}
  /// Called when Return ends editing (after onLeave)
  var onReturn: () -> Void = {}
  /// Whether to keep focus here after Tab or Return (asked after onLeave).
  /// Clicking another field with the mouse always moves focus.
  var keepFocus: () -> Bool = { false }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSSecureTextField {
    let field = NSSecureTextField()
    field.delegate = context.coordinator
    field.stringValue = text
    field.bezelStyle = .roundedBezel
    return field
  }

  func updateNSView(_ field: NSSecureTextField, context: Context) {
    context.coordinator.parent = self
    // Do not write back while editing (while a field editor exists)
    if field.currentEditor() == nil, field.stringValue != text {
      field.stringValue = text
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: SecureInputField

    init(_ parent: SecureInputField) { self.parent = parent }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
      parent.onLeave()
      let movement = notification.userInfo?["NSTextMovement"] as? Int
      let byKey = [NSTextMovement.tab, .backtab, .return].map(\.rawValue).contains(movement)
      if byKey, parent.keepFocus() {
        // Refocus after the move to the next field has finished
        DispatchQueue.main.async {
          field.window?.makeFirstResponder(field)
          field.currentEditor()?.selectAll(nil)
        }
        return
      }
      if movement == NSTextMovement.return.rawValue { parent.onReturn() }
    }
  }
}
