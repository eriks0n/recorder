import AppKit
import SwiftUI

/// A native password control with visible bounds and menu-independent paste.
/// The accessory app does not always have an Edit menu to dispatch Command-V.
struct APIKeyEntryField: NSViewRepresentable {
    @Binding var text: String
    var isEnabled = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> APIKeySecureTextField {
        let field = APIKeySecureTextField(frame: .zero)
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier("todoist-api-key-input")
        field.placeholderString = "API-Key hier eingeben oder einfügen"
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: APIKeySecureTextField, context: Context) {
        context.coordinator.text = $text
        field.isEnabled = isEnabled
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

final class APIKeySecureTextField: NSSecureTextField {
    // Tests supply synthetic text here; they never read or overwrite the user's clipboard.
    var pasteboardString: () -> String? = { NSPasteboard.general.string(forType: .string) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard isEnabled, modifiers == .command, let editor = currentEditor() as? NSTextView,
              window?.firstResponder === editor else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v":
            if let value = pasteboardString() {
                editor.insertText(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return true
        case "a":
            editor.selectAll(self)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
