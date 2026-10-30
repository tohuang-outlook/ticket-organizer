import XCTest
import Darwin
@testable import TicketOrganizer

final class TicketStoreTests: XCTestCase {
    @MainActor
    func testTrafficFlowDisplaysAndPersistsWithLegacyCompatibility() throws {
        XCTAssertEqual(TicketNote.trafficFlowDescription(["FW03", "FW04", "FW05"]), "From FW03 to FW04 to FW05")
        XCTAssertEqual(TicketNote.trafficFlowDescription(["FW01", "FW02", "FW03", "FW04", "FW05"]), "From FW01 to FW02 to FW03 to FW04 to FW05")
        XCTAssertEqual(TicketNote.trafficFlowSlots(["FW03", "FW04", "FW05"]), ["FW03", "FW04", "FW05", "", ""])
        XCTAssertEqual(TicketNote.trafficFlowDescription(["FW03", "", "FW05"]), "From FW03 to FW05")
        XCTAssertEqual(TicketNote.trafficFlowDescription(["", "", ""]), "")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        var note = makeNote()
        note.trafficFlow = ["FW01", "FW02", "FW03", "FW04", "FW05"]
        try store.add(note)
        let reopened = try XCTUnwrap(TicketStore(url: url).notes.first)
        XCTAssertEqual(reopened.trafficFlow, note.trafficFlow)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        json.removeValue(forKey: "trafficFlow")
        let legacy = try JSONDecoder().decode(TicketNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.trafficFlow.isEmpty)
    }

    @MainActor
    func testRITMOnlyWorkingTicketCanBeEditedAndReopened() async throws {
        XCTAssertTrue(TicketStage.draft.allowsIncompleteDetails)
        XCTAssertTrue(TicketStage.working.allowsIncompleteDetails)
        XCTAssertFalse(TicketStage.approval.allowsIncompleteDetails)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let original = TicketNote(ritm: "RITM123456", chg: "", title: "", body: "", stage: .draft, priority: .low, owner: "")
        try store.add(original)
        try store.moveTicket(id: original.id, to: .working)
        var edited = try XCTUnwrap(store.notes.first)
        edited.body = "Work in progress"
        try store.update(edited)
        let reopened = try XCTUnwrap(TicketStore(url: url).notes.first)
        XCTAssertEqual(reopened.stage, .working)
        XCTAssertEqual(reopened.body, edited.body)
        XCTAssertTrue(reopened.chg.isEmpty)
        XCTAssertEqual(reopened.createdAt, original.createdAt)
    }

    @MainActor
    func testBusyWriterLockFailsWithoutOverwritingData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let original = makeNote()
        try store.add(original)
        let before = try Data(contentsOf: url)
        let descriptor = Darwin.open(url.appendingPathExtension("lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try store.delete(original))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(store.notes, [original])
    }

    @MainActor
    func testSecondInstanceCannotOverwriteNewerSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let first = TicketStore(url: url)
        let original = makeNote()
        try first.add(original)
        let second = TicketStore(url: url)
        var updated = original
        updated.title = "Saved by first instance"
        try first.update(updated)
        let savedData = try Data(contentsOf: url)
        XCTAssertThrowsError(try second.delete(original))
        XCTAssertEqual(try Data(contentsOf: url), savedData)
        XCTAssertEqual(second.notes.first?.title, original.title)
        XCTAssertEqual(TicketStore(url: url).notes.first?.title, updated.title)
    }

    @MainActor
    func testRemovedDataFileCannotBeSilentlyRecreatedFromStaleMemory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let original = makeNote()
        try store.add(original)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try store.update(original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testWorkflowOrderAndPersistedValuesRoundTrip() throws {
        XCTAssertEqual(TicketStage.allCases.map(\.shortTitle), ["Draft", "Working", "Pending Approval", "Approved", "Completed", "Important", "Closed"])
        XCTAssertEqual(TicketStage.allCases.map(\.rawValue), ["draft", "working", "approval", "approved", "completed", "example", "closed"])
        for stage in TicketStage.allCases {
            XCTAssertEqual(try JSONDecoder().decode(TicketStage.self, from: JSONEncoder().encode(stage)), stage)
        }
    }

    func testOpenNotesExcludesClosedTickets() {
        let open = makeNote()
        var closed = makeNote()
        closed.stage = .closed
        XCTAssertEqual(TicketNote.excludingClosed([open, closed]), [open])
    }

    func testImportantMarkerRoundTripsAndLegacyImportantTicketsAreMarked() throws {
        var note = makeNote()
        note.isImportant = true
        let marked = try JSONDecoder().decode(TicketNote.self, from: JSONEncoder().encode(note))
        XCTAssertTrue(marked.isImportant)
        XCTAssertEqual(marked.stage, .draft)

        note.isImportant = false
        note.stage = .important
        let legacy = try JSONDecoder().decode(TicketNote.self, from: JSONEncoder().encode(note))
        XCTAssertTrue(legacy.isImportant)
        XCTAssertEqual(legacy.stage, .important)
        XCTAssertEqual(TicketNote.importantTickets([legacy]).count, 1)
        XCTAssertEqual(TicketNote.importantTickets([marked]).count, 1)
    }

    @MainActor
    func testMarkingTicketImportantDoesNotChangeWorkflowStatus() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let original = makeNote()
        try store.add(original)

        var marked = original
        marked.isImportant = true
        try store.update(marked)

        let saved = try XCTUnwrap(TicketStore(url: store.url).notes.first)
        XCTAssertEqual(saved.stage, .draft)
        XCTAssertTrue(saved.isImportant)
    }

    @MainActor
    func testEditorSaveDoesNotUndoImportantSidebarDrop() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let original = makeNote()
        try store.add(original)
        try store.moveTicket(id: original.id, to: .important)

        var editor = original
        editor.body = "Updated note"
        try store.update(editor, originalStage: original.stage, originalIsImportant: original.isImportant)

        let saved = try XCTUnwrap(store.notes.first)
        XCTAssertEqual(saved.stage, .draft)
        XCTAssertTrue(saved.isImportant)
        XCTAssertEqual(saved.body, "Updated note")
    }

    @MainActor
    func testBackupRestoreReplacesSnapshotAndKeepsSafetyCopy() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let backupURL = folder.appendingPathComponent("Ticket Organizer Backup.json")
        let store = TicketStore(url: url)
        let original = makeNote()
        var closed = makeNote()
        closed.stage = .closed
        try store.add(original)
        try store.add(closed)
        try store.exportBackup(to: backupURL)

        var changed = original
        changed.title = "Changed after backup"
        try store.update(changed)
        try store.delete(closed)
        let later = makeNote()
        try store.add(later)

        try store.restoreBackup(from: backupURL)
        let restored = TicketStore(url: url).notes
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.first(where: { $0.id == original.id })?.title, original.title)
        let restoredClosed = try XCTUnwrap(restored.first(where: { $0.stage == .closed }))
        XCTAssertEqual(restoredClosed.ritm, closed.ritm)
        XCTAssertNotEqual(restoredClosed.id, closed.id)
        XCTAssertFalse(restored.contains(where: { $0.id == later.id }))

        let safetyURL = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix("TicketOrganizer-before-restore-") }))
        let safety = try TicketBackupDocument.decode(Data(contentsOf: safetyURL))
        XCTAssertEqual(safety.archive.notes.count, 2)
        XCTAssertTrue(safety.archive.notes.contains(where: { $0.title == "Changed after backup" }))
        XCTAssertTrue(safety.archive.notes.contains(where: { $0.id == later.id }))
    }

    @MainActor
    func testInvalidBackupDoesNotChangeTickets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let badBackup = folder.appendingPathComponent("bad.json")
        let store = TicketStore(url: url)
        let note = makeNote()
        try store.add(note)
        try Data("not a backup".utf8).write(to: badBackup)

        XCTAssertThrowsError(try store.restoreBackup(from: badBackup))
        XCTAssertEqual(TicketStore(url: url).notes, [note])
    }

    @MainActor
    func testExportCannotOverwriteLiveDataOrAutomaticBackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        try store.add(makeNote())
        let before = try Data(contentsOf: url)

        XCTAssertThrowsError(try store.exportBackup(to: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertThrowsError(try store.exportBackup(to: url.appendingPathExtension("backup")))
    }

    @MainActor
    func testBackupFromDifferentBoundCloudAccountIsRejected() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backupURL = folder.appendingPathComponent("account-a.json")
        let accountA = TicketStore(url: folder.appendingPathComponent("a/tickets.json"))
        try accountA.bindCloudAccount("account-a")
        try accountA.add(makeNote())
        try accountA.exportBackup(to: backupURL)

        let accountB = TicketStore(url: folder.appendingPathComponent("b/tickets.json"))
        try accountB.bindCloudAccount("account-b")
        let localNote = makeNote()
        try accountB.add(localNote)
        XCTAssertThrowsError(try accountB.restoreBackup(from: backupURL))
        XCTAssertEqual(TicketStore(url: accountB.url).notes, [localNote])
    }

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
        for stage in TicketStage.allCases where stage != .important {
            try store.moveTicket(id: original.id, to: stage)
            let moved = try XCTUnwrap(TicketStore(url: url).notes.first)
            XCTAssertEqual(moved.stage, stage)
            XCTAssertEqual(moved.createdAt, original.createdAt)
            XCTAssertEqual(moved.body, original.body)
            XCTAssertEqual(moved.richBody, original.richBody)
        }
        try store.moveTicket(id: original.id, to: .important)
        let marked = try XCTUnwrap(TicketStore(url: url).notes.first)
        XCTAssertEqual(marked.stage, .closed)
        XCTAssertTrue(marked.isImportant)
        XCTAssertEqual(marked.createdAt, original.createdAt)
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
        editor.stage = .important
        try store.update(editor, originalStage: original.stage)
        XCTAssertEqual(store.notes.first?.stage, .important)
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
        edited.createdAt = Date(timeIntervalSince1970: 1700000000)
        try store.update(edited)
        let reopened = TicketStore(url: url)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.notes.first?.createdAt, edited.createdAt)
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
