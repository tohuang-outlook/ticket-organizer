import SwiftUI
import AppKit

struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richBody: Data?
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = BoldNoteTextView(frame: .zero)
        editor.isRichText = true
        editor.importsGraphics = false
        editor.isEditable = editable
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.font = .systemFont(ofSize: 16)
        editor.textColor = .textColor
        editor.delegate = context.coordinator
        if let data = richBody, let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            let resized = NSMutableAttributedString(attributedString: attributed)
            resized.enumerateAttribute(.font, in: NSRange(location: 0, length: resized.length)) { value, range, _ in
                let font = value as? NSFont ?? .systemFont(ofSize: 16)
                resized.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: 16), range: range)
            }
            editor.textStorage?.setAttributedString(resized)
        } else {
            editor.string = text
        }
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        init(_ parent: RichNoteEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.richBody = editor.rtf(from: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
        }
    }
}

final class BoldNoteTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditable,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "b" {
            toggleSelectionBold()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func toggleSelectionBold() {
        let range = selectedRange()
        let manager = NSFontManager.shared
        if range.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 16)
            let bold = manager.traits(of: font).contains(.boldFontMask)
            typingAttributes[.font] = bold ? manager.convert(font, toNotHaveTrait: .boldFontMask) : manager.convert(font, toHaveTrait: .boldFontMask)
            return
        }
        guard let storage = textStorage else { return }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let fullRange = NSRange(location: 0, length: replacement.length)
        var allBold = true
        replacement.enumerateAttribute(.font, in: fullRange) { value, _, _ in
            if !manager.traits(of: value as? NSFont ?? .systemFont(ofSize: 16)).contains(.boldFontMask) { allBold = false }
        }
        replacement.enumerateAttribute(.font, in: fullRange) { value, subrange, _ in
            let font = value as? NSFont ?? .systemFont(ofSize: 16)
            let converted = allBold ? manager.convert(font, toNotHaveTrait: .boldFontMask) : manager.convert(font, toHaveTrait: .boldFontMask)
            replacement.addAttribute(.font, value: converted, range: subrange)
        }
        insertText(replacement, replacementRange: range)
        setSelectedRange(range)
        undoManager?.setActionName("Toggle Bold")
    }
}
