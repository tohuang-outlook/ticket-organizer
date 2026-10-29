import XCTest
import AppKit
import SwiftUI
@testable import TicketOrganizer

final class RichTextTests: XCTestCase {
    @MainActor
    func testItalicShortcutAndButtonPreserveBoldAndSaveFormatting() throws {
        var text = "first second"
        var richBody: Data?
        let controller = NoteFontSizeController()
        let parent = RichNoteEditor(text: Binding(get: { text }, set: { text = $0 }),
                                    richBody: Binding(get: { richBody }, set: { richBody = $0 }),
                                    fontSize: .constant(16), sizeController: controller)
        let coordinator = parent.makeCoordinator()
        let editor = BoldNoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        editor.isRichText = true
        editor.isEditable = true
        editor.font = .systemFont(ofSize: 16)
        editor.string = text
        editor.delegate = coordinator
        coordinator.connectSizeController(controller, to: editor)
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        func event(_ character: String, keyCode: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
        }
        let bold = try event("b", keyCode: 11)
        let italic = try event("i", keyCode: 34)
        XCTAssertTrue(editor.performKeyEquivalent(with: bold))
        XCTAssertTrue(editor.performKeyEquivalent(with: italic))
        let saved = try XCTUnwrap(richBody)
        let reopened = try XCTUnwrap(RichNoteEditor.restoredBody(from: saved))
        let selected = try XCTUnwrap(reopened.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let unselected = try XCTUnwrap(reopened.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: selected).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: selected).contains(.italicFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: unselected).contains(.italicFontMask))
        XCTAssertEqual(selected.pointSize, 16)
        controller.toggleItalic()
        let toggled = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: toggled).contains(.boldFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: toggled).contains(.italicFontMask))
        editor.setSelectedRange(NSRange(location: 12, length: 0))
        XCTAssertTrue(editor.performKeyEquivalent(with: italic))
        let typingFont = try XCTUnwrap(editor.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: typingFont).contains(.italicFontMask))
    }

    @MainActor
    func testSelectedFontSizeChangesAccumulateAndSurviveRTF() throws {
        var text = "first second"
        var richBody: Data?
        var fontSize = 16
        let controller = NoteFontSizeController()
        let parent = RichNoteEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            richBody: Binding(get: { richBody }, set: { richBody = $0 }),
            fontSize: Binding(get: { fontSize }, set: { fontSize = $0 }),
            sizeController: controller
        )
        let coordinator = parent.makeCoordinator()
        let editor = BoldNoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        editor.isRichText = true
        editor.isEditable = true
        editor.allowsUndo = true
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: editor.frame)
        scroll.documentView = editor
        window.contentView = scroll
        editor.font = .systemFont(ofSize: 16)
        editor.string = text
        editor.textStorage?.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 16), range: NSRange(location: 6, length: 6))
        editor.delegate = coordinator
        coordinator.connectSizeController(controller, to: editor)
        editor.setSelectedRange(NSRange(location: 6, length: 6))

        func size(at index: Int) throws -> CGFloat {
            try XCTUnwrap(editor.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont).pointSize
        }

        let undo = try XCTUnwrap(editor.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        controller.adjustSelection(by: 2)
        undo.endUndoGrouping()
        XCTAssertEqual(try size(at: 0), 16)
        XCTAssertEqual(try size(at: 6), 18)
        XCTAssertEqual(controller.selectionFontSize, 18)
        undo.undo()
        XCTAssertEqual(try size(at: 6), 16)
        XCTAssertEqual(controller.selectionFontSize, 16)
        undo.redo()
        XCTAssertEqual(try size(at: 6), 18)
        XCTAssertEqual(controller.selectionFontSize, 18)
        undo.beginUndoGrouping()
        controller.adjustSelection(by: 2)
        XCTAssertEqual(try size(at: 6), 20)
        controller.adjustSelection(by: -2)
        undo.endUndoGrouping()
        XCTAssertEqual(try size(at: 6), 18)
        let saved = try XCTUnwrap(richBody)
        let reopened = try XCTUnwrap(RichNoteEditor.restoredBody(from: saved))
        XCTAssertEqual((reopened.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 16)
        let selectedFont = try XCTUnwrap(reopened.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(selectedFont.pointSize, 18)
        XCTAssertTrue(NSFontManager.shared.traits(of: selectedFont).contains(.boldFontMask))
        undo.beginUndoGrouping()
        coordinator.adjustFontSize(by: 2, in: editor)
        undo.endUndoGrouping()
        XCTAssertEqual(try size(at: 0), 18)
        XCTAssertTrue(NSFontManager.shared.traits(of: try XCTUnwrap(editor.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)).contains(.boldFontMask))
    }

    @MainActor
    func testCommandBBoldsOnlySelectionAndSurvivesRTFSave() async throws {
        let editor = BoldNoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        editor.isRichText = true
        editor.isEditable = true
        editor.font = .systemFont(ofSize: 16)
        editor.string = "first second"
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))
        XCTAssertTrue(editor.performKeyEquivalent(with: event))
        let data = try XCTUnwrap(editor.rtf(from: NSRange(location: 0, length: 12)))
        let reopened = try XCTUnwrap(NSAttributedString(rtf: data, documentAttributes: nil))
        let selectedFont = try XCTUnwrap(reopened.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let otherFont = try XCTUnwrap(reopened.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: selectedFont).contains(.boldFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: otherFont).contains(.boldFontMask))
        XCTAssertEqual(selectedFont.pointSize, 16)
        XCTAssertEqual(reopened.string, "first second")
        XCTAssertTrue(editor.performKeyEquivalent(with: event))
        let toggled = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: toggled).contains(.boldFontMask))
    }
}
