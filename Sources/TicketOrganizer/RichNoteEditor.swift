import SwiftUI
import AppKit

struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richBody: Data?
    @Binding var fontSize: Int
    var editable = true

    static func preferredFontSize(from richBody: Data?) -> Int {
        guard let richBody,
              let attributed = NSAttributedString(rtf: richBody, documentAttributes: nil),
              attributed.length > 0 else { return 16 }
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        return min(48, max(10, Int((font?.pointSize ?? 16).rounded())))
    }

    private func resized(_ attributed: NSAttributedString, to size: Int) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        guard result.length > 0 else { return result }
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            let font = value as? NSFont ?? .systemFont(ofSize: CGFloat(size))
            result.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: CGFloat(size)), range: range)
        }
        return result
    }

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
        editor.font = .systemFont(ofSize: CGFloat(fontSize))
        editor.textColor = .textColor
        editor.delegate = context.coordinator
        editor.onFontSizeAdjustment = { [weak coordinator = context.coordinator, weak editor] step in
            guard let editor else { return }
            coordinator?.adjustFontSize(by: step, in: editor)
        }
        if let data = richBody, let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            editor.textStorage?.setAttributedString(resized(attributed, to: fontSize))
        } else {
            editor.string = text
        }
        context.coordinator.appliedFontSize = fontSize
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.appliedFontSize != fontSize,
              let editor = scroll.documentView as? BoldNoteTextView else { return }
        context.coordinator.applyFontSize(fontSize, to: editor, notifyChange: true)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        var appliedFontSize = 16
        init(_ parent: RichNoteEditor) { self.parent = parent }

        func adjustFontSize(by step: Int, in editor: BoldNoteTextView) {
            let size = min(48, max(10, parent.fontSize + step))
            guard size != parent.fontSize else { return }
            parent.fontSize = size
            applyFontSize(size, to: editor, notifyChange: true)
        }

        func applyFontSize(_ size: Int, to editor: BoldNoteTextView, notifyChange: Bool) {
            let selection = editor.selectedRange()
            if let storage = editor.textStorage, storage.length > 0 {
                let resized = NSMutableAttributedString(attributedString: storage)
                resized.enumerateAttribute(.font, in: NSRange(location: 0, length: resized.length)) { value, range, _ in
                    let font = value as? NSFont ?? .systemFont(ofSize: CGFloat(size))
                    resized.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: CGFloat(size)), range: range)
                }
                editor.insertText(resized, replacementRange: NSRange(location: 0, length: storage.length))
                editor.setSelectedRange(NSRange(location: min(selection.location, resized.length), length: min(selection.length, max(0, resized.length - selection.location))))
                editor.undoManager?.setActionName("Change Note Font Size")
                if notifyChange { editor.didChangeText() }
            }
            var attributes = editor.typingAttributes
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: CGFloat(size))
            attributes[.font] = NSFontManager.shared.convert(font, toSize: CGFloat(size))
            editor.typingAttributes = attributes
            appliedFontSize = size
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            parent.richBody = editor.rtf(from: NSRange(location: 0, length: editor.textStorage?.length ?? 0))
        }
    }
}

final class BoldNoteTextView: NSTextView {
    var onFontSizeAdjustment: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditable, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "b" {
            toggleSelectionBold()
            return true
        }
        if key == "." {
            onFontSizeAdjustment?(2)
            return true
        }
        if key == "-" {
            onFontSizeAdjustment?(-2)
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
