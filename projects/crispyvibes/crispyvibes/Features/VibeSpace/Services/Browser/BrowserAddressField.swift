import AppKit
import SwiftUI

/// NSTextField wrapper that intercepts arrow keys for suggestion navigation
/// via the field editor delegate, where SwiftUI's TextField cannot.
struct BrowserAddressField: NSViewRepresentable {
    @Environment(\.crispyvibesUIScale) private var uiScale

    @Binding var text: String
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onEscape: () -> Void

    var autoFocus: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        applyScale(to: field)
        field.placeholderString = AppStrings.Browser.addressBarPlaceholder
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byTruncatingTail
        if autoFocus {
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        applyScale(to: nsView)
        context.coordinator.parent = self
    }

    private func applyScale(to field: NSTextField) {
        let targetFont = NSFont.systemFont(ofSize: uiScale.textSize(12))
        if field.font?.fontName != targetFont.fontName ||
            abs((field.font?.pointSize ?? 0) - targetFont.pointSize) > 0.1 {
            field.font = targetFont
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField

        init(parent: BrowserAddressField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}
