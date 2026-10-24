import XCTest
@testable import TicketOrganizer

final class TicketStoreTests: XCTestCase {
    @MainActor
    func testRITMOnlyDraftCanBeSavedReopenedAndCompleted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let draft = TicketNote(ritm: "RITM123456", chg: "", title: "", body: "", stage: .draft, priority: .medium, owner: "")
        try store.add(draft)
        let reopened = TicketStore(url: url)
        var saved = try XCTUnwrap(reopened.notes.first)
        XCTAssertEqual(saved.ritm, draft.ritm)
        XCTAssertTrue(saved.chg.isEmpty)
        XCTAssertTrue(saved.title.isEmpty)
        XCTAssertTrue(saved.body.isEmpty)
        saved.body = "Continue drafting"
        try reopened.update(saved)
        XCTAssertEqual(TicketStore(url: url).notes.first?.body, saved.body)
        saved = try XCTUnwrap(TicketStore(url: url).notes.first)
        saved.chg = "CHG123"
        saved.title = "Completed note"
        try reopened.update(saved)
        XCTAssertEqual(TicketStore(url: url).notes.first?.chg, saved.chg)
    }

    @MainActor
    func testWorkflowDropsPersistWithoutChangingNoteOrCreationTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        var original = makeNote()
        original.richBody = Data([1, 2, 3])
        try store.add(original)
        for stage in TicketStage.allCases {
            try store.moveTicket(id: original.id, to: stage)
            let moved = try XCTUnwrap(TicketStore(url: url).notes.first)
            XCTAssertEqual(moved.stage, stage)
            XCTAssertEqual(moved.createdAt, original.createdAt)
            XCTAssertEqual(moved.body, original.body)
            XCTAssertEqual(moved.richBody, original.richBody)
        }
        XCTAssertThrowsError(try store.moveTicket(id: UUID(), to: .approved))
        XCTAssertEqual(store.notes.count, 1)
    }

    @MainActor
    func testEditorDoesNotRevertWorkflowDropWhenStatusWasUntouched() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let original = makeNote()
        try store.add(original)
        try store.moveTicket(id: original.id, to: .approved)
        var editor = original
        editor.body = "Edited while dragging"
        try store.update(editor, originalStage: original.stage)
        XCTAssertEqual(store.notes.first?.stage, .approved)
        XCTAssertEqual(store.notes.first?.body, editor.body)
        editor = try XCTUnwrap(store.notes.first)
        editor.stage = .example
        try store.update(editor, originalStage: original.stage)
        XCTAssertEqual(store.notes.first?.stage, .example)
    }

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
        let backup = try TicketArchive.decode(Data(contentsOf: url.appendingPathExtension("backup"))).notes
        XCTAssertEqual(backup.first?.title, original.title)
        XCTAssertEqual(TicketStore(url: url).notes.first?.title, updated.title)
    }
}
