import XCTest
@testable import TicketOrganizer

final class CreationDateTests: XCTestCase {
    func testManualCreationTimeValidatesLeapDaysAndMissingDSTHour() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertNotNil(CreatedTimeInput.parse("2028-02-29 09:30:00", timeZone: zone))
        XCTAssertNil(CreatedTimeInput.parse("2026-02-29 09:30:00", timeZone: zone))
        XCTAssertNil(CreatedTimeInput.parse("2026-03-08 02:30:00", timeZone: zone))
    }

    func testManuallyEnteredCreationTimeRoundTripsWithSeconds() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let text = "2026-10-23 21:37:04"
        let date = try XCTUnwrap(CreatedTimeInput.parse(text, timeZone: zone))
        XCTAssertEqual(CreatedTimeInput.format(date, timeZone: zone), text)
        XCTAssertEqual(CreatedTimeInput.parse("  \(text)  ", timeZone: zone), date)
    }

    func testManualCreationTimeRejectsInvalidDatesAndFormats() {
        for text in ["", "2026-02-30 12:00:00", "2026-13-01 12:00:00", "2026-10-23 25:00:00", "2026-10-23 12:00:60", "10/23/2026", "2026-1-2 01:02:03"] {
            XCTAssertNil(CreatedTimeInput.parse(text), text)
        }
    }

    func testSortingUsesCreationTimeInsteadOfLastEditTime() {
        var older = note()
        var newer = note()
        older.createdAt = Date(timeIntervalSince1970: 100)
        older.updatedAt = Date(timeIntervalSince1970: 900)
        newer.createdAt = Date(timeIntervalSince1970: 200)
        newer.updatedAt = Date(timeIntervalSince1970: 300)
        XCTAssertEqual(TicketNote.sortedByCreation([older, newer], newestFirst: true).map(\.id), [newer.id, older.id])
        XCTAssertEqual(TicketNote.sortedByCreation([newer, older], newestFirst: false).map(\.id), [older.id, newer.id])
    }

    private func note() -> TicketNote {
        TicketNote(ritm: "RITM001", chg: "CHG001", title: "Test", body: "Original text", stage: .draft, priority: .medium, owner: "", updatedAt: Date(timeIntervalSince1970: 1700000000), richBody: Data([1, 2, 3]), createdAt: Date(timeIntervalSince1970: 1600000000))
    }

    func testLegacyNoteUsesLastUpdateAsStableCreationDate() throws {
        let original = note()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "createdAt")
        var migrated = try JSONDecoder().decode(TicketNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.createdAt, original.updatedAt)
        XCTAssertEqual(migrated.body, original.body)
        XCTAssertEqual(migrated.richBody, original.richBody)
        migrated.updatedAt = Date()
        let reopened = try JSONDecoder().decode(TicketNote.self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(reopened.createdAt, original.updatedAt)
    }

    func testChosenCreationDateSurvivesEditAndReload() throws {
        var edited = note()
        let created = edited.createdAt
        edited.title = "Edited"
        edited.updatedAt = Date()
        let reopened = try JSONDecoder().decode(TicketNote.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(reopened.createdAt, created)
        XCTAssertEqual(reopened.title, "Edited")
        XCTAssertEqual(reopened.richBody, edited.richBody)
    }
}
