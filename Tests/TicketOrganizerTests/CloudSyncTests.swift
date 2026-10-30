import XCTest
@testable import TicketOrganizer

@MainActor
private final class MockTicketCloud: TicketCloudTransport {
    var account = "account-A"
    var records: [String: TicketSyncRecord] = [:]
    var offline = false
    var fetchCount = 0
    var saveCount = 0
    var afterFetch: (() -> Void)?
    func accountID() async throws -> String { account }
    func fetchRecords() async throws -> [TicketSyncRecord] {
        fetchCount += 1
        if offline { throw URLError(.notConnectedToInternet) }
        afterFetch?()
        return Array(records.values)
    }
    func saveRecords(_ changes: [TicketSyncRecord]) async throws -> [TicketCloudSaveResult] {
        saveCount += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return changes.map {
            var saved = $0
            saved.uploadedRevision = saved.revision
            records[saved.id.uuidString] = saved
            return .saved(saved)
        }
    }
}

final class CloudSyncTests: XCTestCase {
    @MainActor
    func testAccountSwitchDuringFetchDoesNotMergeOrUpload() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let original = note()
        try store.add(original)
        let cloud = MockTicketCloud()
        cloud.records[UUID().uuidString] = TicketSyncRecord(note: note())
        cloud.afterFetch = { cloud.account = "account-B" }
        let sync = TicketCloudSync(store: store, transport: cloud, automatic: false)
        try sync.setEnabled(true)
        await sync.syncNow()
        XCTAssertEqual(cloud.saveCount, 0)
        XCTAssertEqual(store.notes, [original])
        XCTAssertEqual(store.archive.cloudAccountID, "account-A")
    }

    @MainActor
    func testFirstWriteBacksUpOriginalLegacyFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("tickets.json")
        let original = note()
        let data = try JSONEncoder().encode([original])
        try data.write(to: url)
        let store = TicketStore(url: url)
        try store.setSyncEnabled(true)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("pre-icloud-backup")), data)
        let reopened = TicketStore(url: url)
        XCTAssertEqual(reopened.notes, [original])
        XCTAssertTrue(reopened.archive.syncEnabled)
    }

    @MainActor
    func testStaleEditorCannotOverwriteRemoteContent() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let original = note()
        try store.add(original)
        try store.bindCloudAccount("account-A")
        var remote = TicketSyncRecord(note: original)
        var edited = original
        edited.body = "Edited on the other Mac"
        edited.updatedAt = original.updatedAt.addingTimeInterval(10)
        remote.change(to: edited)
        remote.changedAt = edited.updatedAt
        try store.applyCloudRecords([remote], accountID: "account-A")
        XCTAssertThrowsError(try store.update(original))
        XCTAssertEqual(store.notes.first?.body, edited.body)
    }

    private func note() -> TicketNote {
        TicketNote(ritm: "RITM1234567", chg: "", title: "Original", body: "Local note", stage: .draft, priority: .low, owner: "", richBody: Data([1, 2]), createdAt: Date(timeIntervalSince1970: 1600000000))
    }

    func testLegacyMigrationRetainsDataAndQueuesFirstUpload() throws {
        let original = note()
        let archive = try TicketArchive.decode(JSONEncoder().encode([original]))
        XCTAssertEqual(archive.notes, [original])
        XCTAssertEqual(archive.pendingRecords.count, 1)
        XCTAssertFalse(archive.syncEnabled)
        let reopened = try TicketArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(reopened.notes, [original])
        XCTAssertEqual(reopened.pendingRecords.first?.revision, archive.pendingRecords.first?.revision)
    }

    func testRemoteDeletionWinsOverOldOfflineNote() {
        let record = TicketSyncRecord(note: note())
        var archive = TicketArchive()
        archive.records[record.id.uuidString] = record
        var deletion = record
        deletion.change(to: nil)
        archive.merge(deletion)
        XCTAssertTrue(archive.notes.isEmpty)
        XCTAssertNil(archive.records[record.id.uuidString]?.note)
        // Replaying an older live version cannot resurrect the ticket.
        archive.merge(record)
        XCTAssertTrue(archive.notes.isEmpty)
        var futureOfflineEdit = record
        futureOfflineEdit.revision = UUID()
        futureOfflineEdit.changedAt = deletion.changedAt.addingTimeInterval(86400)
        archive.merge(futureOfflineEdit)
        XCTAssertTrue(archive.notes.isEmpty)
        XCTAssertFalse(archive.conflicts.isEmpty)
    }

    func testConcurrentEditsKeepRecoverableLosingVersion() {
        let original = note()
        var local = TicketSyncRecord(note: original)
        local.uploadedRevision = UUID()
        var remote = local
        var edited = original
        edited.body = "Other Mac version"
        remote.change(to: edited)
        remote.changedAt = local.changedAt.addingTimeInterval(1)
        var archive = TicketArchive()
        archive.records[local.id.uuidString] = local
        archive.merge(remote)
        XCTAssertEqual(archive.notes.first?.body, edited.body)
        XCTAssertEqual(archive.conflicts.first?.note.body, original.body)
        XCTAssertEqual(archive.conflicts.first?.note.richBody, original.richBody)
        archive.merge(remote)
        XCTAssertEqual(archive.conflicts.count, 1)
    }

    func testUploadAcknowledgmentDoesNotEraseNewerEdit() {
        let uploaded = TicketSyncRecord(note: note())
        var newer = uploaded
        var edited = note()
        edited.id = uploaded.id
        edited.body = "Edited during upload"
        newer.change(to: edited)
        var archive = TicketArchive()
        archive.records[uploaded.id.uuidString] = newer
        archive.acknowledge(uploaded)
        XCTAssertEqual(archive.notes.first?.body, edited.body)
        XCTAssertTrue(archive.records[uploaded.id.uuidString]!.isPending)
    }

    @MainActor
    func testTwoDevicesMergeAndSynchronizeDeletions() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = TicketStore(url: folder.appendingPathComponent("first.json"))
        let second = TicketStore(url: folder.appendingPathComponent("second.json"))
        let cloud = MockTicketCloud()
        let syncA = TicketCloudSync(store: first, transport: cloud, automatic: false)
        let syncB = TicketCloudSync(store: second, transport: cloud, automatic: false)
        var original = note()
        original.trafficFlow = ["FW01", "FW02"]
        original.firewallZones = [["zone 2", "zone 1"], ["zone 3", "zone 4"]]
        try first.add(original)
        try syncA.setEnabled(true)
        try syncB.setEnabled(true)
        await syncA.syncNow()
        await syncB.syncNow()
        XCTAssertEqual(second.notes, first.notes)
        XCTAssertTrue(first.archive.pendingRecords.isEmpty)
        try first.moveTicket(id: original.id, to: .working)
        await syncA.syncNow()
        await syncB.syncNow()
        XCTAssertEqual(second.notes.first?.stage, .working)
        XCTAssertEqual(second.notes.first?.createdAt, original.createdAt)
        XCTAssertEqual(TicketStore(url: second.url).notes.first?.stage, .working)
        try first.moveTicket(id: original.id, to: .closed)
        await syncA.syncNow()
        await syncB.syncNow()
        XCTAssertEqual(second.notes.first?.stage, .closed)
        XCTAssertEqual(second.notes.first?.createdAt, original.createdAt)
        XCTAssertEqual(TicketStore(url: second.url).notes.first?.stage, .closed)
        try second.delete(original)
        await syncB.syncNow()
        await syncA.syncNow()
        XCTAssertTrue(first.notes.isEmpty)
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertNotNil(first.archive.records[original.id.uuidString])
    }

    @MainActor
    func testOfflineQueueSurvivesRestartAndReconnects() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        let cloud = MockTicketCloud()
        cloud.offline = true
        let sync = TicketCloudSync(store: store, transport: cloud, automatic: false)
        try store.add(note())
        try sync.setEnabled(true)
        await sync.syncNow()
        XCTAssertEqual(sync.status, "iCloud Sync Paused")
        let reopened = TicketStore(url: url)
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertEqual(reopened.archive.pendingRecords.count, 1)
        cloud.offline = false
        let retry = TicketCloudSync(store: reopened, transport: cloud, automatic: false)
        await retry.syncNow()
        XCTAssertEqual(retry.status, "iCloud Up to Date")
        XCTAssertTrue(reopened.archive.pendingRecords.isEmpty)
    }

    @MainActor
    func testDifferentAccountCannotReadOrUploadExistingNotes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        try store.add(note())
        try store.bindCloudAccount("account-A")
        let cloud = MockTicketCloud()
        cloud.account = "account-B"
        let sync = TicketCloudSync(store: store, transport: cloud, automatic: false)
        try sync.setEnabled(true)
        await sync.syncNow()
        XCTAssertEqual(cloud.fetchCount, 0)
        XCTAssertEqual(cloud.saveCount, 0)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.archive.cloudAccountID, "account-A")
    }

    @MainActor
    func testSyncIsOffUntilEnabled() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        try store.add(note())
        let cloud = MockTicketCloud()
        let sync = TicketCloudSync(store: store, transport: cloud, automatic: false)
        await sync.syncNow()
        XCTAssertEqual(cloud.fetchCount, 0)
        XCTAssertEqual(cloud.saveCount, 0)
    }
}
