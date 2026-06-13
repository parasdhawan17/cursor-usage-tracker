import AppKit
import SwiftUI

/// AppKit text field so paste / ⌘V work in the menu bar panel (SwiftUI SecureField often does not).
struct TokenInputField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        if #available(macOS 14.0, *) {
            field.backgroundColor = NSColor.quaternarySystemFill
        } else {
            field.backgroundColor = NSColor.controlBackgroundColor
        }
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderString = "Paste token here"
        field.delegate = context.coordinator
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.focusRingType = .default
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastFocusToken = -1

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

enum PasteboardToken {
    static func readString() -> String? {
        let pb = NSPasteboard.general
        if let value = pb.string(forType: .string) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
