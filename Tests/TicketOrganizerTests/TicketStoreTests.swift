import XCTest
@testable import TicketOrganizer

final class TicketStoreTests: XCTestCase {
    private func makeNote() -> TicketNote {
        TicketNote(ritm: "RITM001", chg: "CHG001", title: "Test ticket", body: "Notes", stage: .draft, priority: .medium, owner: "", createdAt: Date(timeIntervalSince1970: 1600000000))
    }

    @MainActor
    func testCreateEditApproveDeleteAndReload() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let original = makeNote()
        try store.add(original)
        var edited = original
        edited.body = "Edited notes"
        edited.richBody = Data([1, 2, 3])
        edited.stage = .approved
        edited.createdAt = Date() // Editing must not change creation time.
        try store.update(edited)
        let reopened = TicketStore(url: url)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.notes.first?.createdAt, original.createdAt)
        XCTAssertEqual(reopened.notes.first?.body, "Edited notes")
        XCTAssertEqual(reopened.notes.first?.stage, .approved)
        XCTAssertEqual(reopened.notes.first?.richBody, edited.richBody)
        try reopened.delete(original) // Identify by UUID, not an outdated value snapshot.
        XCTAssertTrue(TicketStore(url: url).notes.isEmpty)
        XCTAssertThrowsError(try reopened.update(edited))
    }

    @MainActor
    func testCorruptFileIsPreservedAndCannotBeOverwritten() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("tickets.json")
        let corrupt = Data("corrupt file".utf8)
        try corrupt.write(to: url)
        let store = TicketStore(url: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.add(makeNote()))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        XCTAssertTrue(store.notes.isEmpty)
    }

    @MainActor
    func testFailedSaveDoesNotChangeInMemoryState() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data("blocking file".utf8).write(to: blocked)
        let store = TicketStore(url: blocked.appendingPathComponent("tickets.json"))
        XCTAssertThrowsError(try store.add(makeNote()))
        XCTAssertTrue(store.notes.isEmpty)
    }

    @MainActor
    func testPreviousValidSaveIsBackedUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let original = makeNote()
        try store.add(original)
        var updated = original
        updated.title = "Changed title"
        try store.update(updated)
        let backup = try JSONDecoder().decode([TicketNote].self, from: Data(contentsOf: url.appendingPathExtension("backup")))
        XCTAssertEqual(backup.first?.title, original.title)
        XCTAssertEqual(TicketStore(url: url).notes.first?.title, updated.title)
    }
}
