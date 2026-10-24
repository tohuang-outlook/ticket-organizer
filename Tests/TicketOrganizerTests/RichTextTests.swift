import XCTest
import AppKit
@testable import TicketOrganizer

final class RichTextTests: XCTestCase {
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
