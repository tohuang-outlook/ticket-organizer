import XCTest
import AppKit
@testable import TicketOrganizer

final class ScreenshotTicketImportTests: XCTestCase {
    func testAssociatesOnlyUnambiguousDatesInSameRow() {
        func box(_ text: String, _ y: Double) -> ScreenshotTextBox { ScreenshotTextBox(text: text, rect: CGRect(x: 0, y: y, width: 0.2, height: 0.02)) }
        let boxes = [box("RITM12345", 0.8), box("2026-11-05 10:41:02", 0.8), box("RITM99999", 0.7), box("2026-11-06 10:00:00", 0.4)]
        let rows = ScreenshotTicketParser.parse(boxes)
        XCTAssertEqual(rows.map(\.number), ["RITM12345", "RITM99999"])
        XCTAssertEqual(rows.map(\.created), ["2026-11-05 10:41:02", ""])
        let ambiguous = ScreenshotTicketParser.parse([box("RITM12345 RITM99999", 0.8), box("2026-11-05 10:41:02", 0.8)])
        XCTAssertTrue(ambiguous.allSatisfy { $0.created.isEmpty })
    }
    func testRecognizesScreenshotWithDates() throws {
        let image = NSImage(size: NSSize(width: 900, height: 220))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 220).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
        ("RITM0774322" as NSString).draw(at: NSPoint(x: 30, y: 140), withAttributes: attributes)
        ("2026-11-05 10:41:02" as NSString).draw(at: NSPoint(x: 420, y: 140), withAttributes: attributes)
        ("RITM0774027" as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: attributes)
        ("2026-11-04 16:48:39" as NSString).draw(at: NSPoint(x: 420, y: 70), withAttributes: attributes)
        image.unlockFocus()
        let data = try XCTUnwrap(image.tiffRepresentation)
        let rows = try ScreenshotTicketParser.recognize(data)
        XCTAssertEqual(rows.map(\.number), ["RITM0774322", "RITM0774027"])
        XCTAssertEqual(rows.map(\.created), ["2026-11-05 10:41:02", "2026-11-04 16:48:39"])
    }
    @MainActor func testImportIsAtomicAndChecksClosedTickets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TicketStore(url: dir.appendingPathComponent("tickets.json"))
        func ticket(_ number: String, _ stage: TicketStage) -> TicketNote {
            TicketNote(ritm: number, chg: "", title: "", body: "", stage: stage, priority: .low, owner: "")
        }
        try store.add(ticket("RITM123", .closed))
        XCTAssertThrowsError(try store.importDrafts([ticket("RITM456", .draft), ticket("ritm123", .draft)]))
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertThrowsError(try store.importDrafts([ticket("RITM456", .draft), ticket("RITM456", .draft)]))
        XCTAssertEqual(store.notes.count, 1)
        try store.importDrafts([ticket("RITM456", .draft), ticket("RITM789", .draft)])
        let reopened = TicketStore(url: store.url)
        XCTAssertEqual(reopened.notes.count, 3)
        XCTAssertEqual(reopened.notes.filter { $0.stage == .draft }.count, 2)
    }
}
