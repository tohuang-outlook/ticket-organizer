import SwiftUI
import AppKit

@MainActor
final class NoteFontSizeController: ObservableObject {
    @Published private(set) var selectionFontSize: Int?
    fileprivate var onAdjustSelection: ((Int) -> Void)?

    func adjustSelection(by step: Int) {
        onAdjustSelection?(step)
    }

    fileprivate func updateSelectionFontSize(_ size: Int?) {
        selectionFontSize = size.map { min(48, max(10, $0)) }
    }
}

struct RichNoteEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richBody: Data?
    @Binding var fontSize: Int
    var sizeController: NoteFontSizeController? = nil
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
        context.coordinator.connectSizeController(sizeController, to: editor)
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
        context.coordinator.connectSizeController(sizeController, to: scroll.documentView as? BoldNoteTextView)
        guard context.coordinator.appliedFontSize != fontSize,
              let editor = scroll.documentView as? BoldNoteTextView else { return }
        context.coordinator.applyFontSize(fontSize, to: editor, notifyChange: true)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.sizeController?.onAdjustSelection = nil
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        var appliedFontSize = 16
        weak var sizeController: NoteFontSizeController?
        init(_ parent: RichNoteEditor) { self.parent = parent }

        func connectSizeController(_ controller: NoteFontSizeController?, to editor: BoldNoteTextView?) {
            sizeController = controller
            controller?.onAdjustSelection = { [weak self, weak editor] step in
                guard let self, let editor else { return }
                self.adjustSelectedFontSize(by: step, in: editor)
            }
        }

        func adjustFontSize(by step: Int, in editor: BoldNoteTextView) {
            let size = min(48, max(10, parent.fontSize + step))
            guard size != parent.fontSize else { return }
            parent.fontSize = size
            applyFontSize(size, to: editor, notifyChange: true)
        }

        func applyFontSize(_ size: Int, to editor: BoldNoteTextView, notifyChange: Bool) {
            let selection = editor.selectedRange()
            let scrollView = editor.enclosingScrollView
            let clipView = scrollView?.contentView
            let scrollOrigin = clipView?.bounds.origin ?? .zero
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

            // Replacing the entire attributed string moves NSTextView's insertion
            // point to the end and scrolls there. Restore the viewport after layout.
            restoreViewport(of: editor, in: scrollView, to: scrollOrigin)
            refreshSelectionFontSize(in: editor)
            Task { @MainActor [weak self, weak scrollView, weak editor] in
                guard let self, let scrollView, let editor else { return }
                self.restoreViewport(of: editor, in: scrollView, to: scrollOrigin)
            }
        }

        private func adjustSelectedFontSize(by step: Int, in editor: BoldNoteTextView) {
            let range = editor.selectedRange()
            guard range.length > 0, let storage = editor.textStorage, NSMaxRange(range) <= storage.length else { return }
            let currentFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: CGFloat(parent.fontSize))
            let size = min(48, max(10, Int(currentFont.pointSize.rounded()) + step))
            guard size != Int(currentFont.pointSize.rounded()) else { return }

            let scrollView = editor.enclosingScrollView
            let clipView = scrollView?.contentView
            let scrollOrigin = clipView?.bounds.origin ?? .zero
            let resized = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            resized.enumerateAttribute(.font, in: NSRange(location: 0, length: resized.length)) { value, subrange, _ in
                let font = value as? NSFont ?? currentFont
                resized.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: CGFloat(size)), range: subrange)
            }
            editor.insertText(resized, replacementRange: range)
            editor.setSelectedRange(range)
            editor.undoManager?.setActionName("Change Selected Text Size")
            editor.didChangeText()
            sizeController?.updateSelectionFontSize(size)
            restoreViewport(of: editor, in: scrollView, to: scrollOrigin)
            Task { @MainActor [weak self, weak editor, weak scrollView] in
                guard let self, let editor else { return }
                self.restoreViewport(of: editor, in: scrollView, to: scrollOrigin)
            }
        }

        private func restoreViewport(of editor: BoldNoteTextView, in scrollView: NSScrollView?, to origin: NSPoint) {
            guard let scrollView else { return }
            if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
            scrollView.layoutSubtreeIfNeeded()
            let clipView = scrollView.contentView
            let documentSize = scrollView.documentView?.bounds.size ?? .zero
            let maxX = max(0, documentSize.width - clipView.bounds.width)
            let maxY = max(0, documentSize.height - clipView.bounds.height)
            clipView.scroll(to: NSPoint(x: min(origin.x, maxX), y: min(origin.y, maxY)))
            scrollView.reflectScrolledClipView(clipView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            refreshSelectionFontSize(in: editor)
        }

        private func refreshSelectionFontSize(in editor: NSTextView) {
            guard let controller = sizeController else { return }
            let range = editor.selectedRange()
            guard range.length > 0,
                  let storage = editor.textStorage,
                  range.location < storage.length,
                  let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else {
                controller.updateSelectionFontSize(nil)
                return
            }
            controller.updateSelectionFontSize(Int(font.pointSize.rounded()))
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
        if handleEditorShortcut(with: event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleEditorShortcut(with: event) { return }
        super.keyDown(with: event)
    }

    private func handleEditorShortcut(with event: NSEvent) -> Bool {
        guard isEditable else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else { return false }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if key == "b" {
            toggleSelectionBold()
            return true
        }
        if key == "." || event.keyCode == 47 {
            onFontSizeAdjustment?(2)
            return true
        }
        if key == "-" || event.keyCode == 27 || event.keyCode == 78 {
            onFontSizeAdjustment?(-2)
            return true
        }
        if key == "+" || (event.keyCode == 24 && modifiers.contains(.shift)) {
            onFontSizeAdjustment?(2)
            return true
        }
        return false
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
