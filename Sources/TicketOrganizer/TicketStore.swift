import Foundation
import Combine
import Darwin

@MainActor
final class TicketStore: ObservableObject {
    @Published private(set) var notes: [TicketNote] = []
    @Published private(set) var archive = TicketArchive()
    @Published var errorMessage: String?
    let url: URL
    private var canWrite = true
    private var lastSavedData: Data?
    var onLocalChange: (() -> Void)?
    lazy var cloudSync = TicketCloudSync(store: self)

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TicketOrganizer/tickets.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let data = try Data(contentsOf: self.url)
                archive = try TicketArchive.decode(data)
                lastSavedData = data
                notes = archive.notes
            }
        } catch {
            canWrite = false
            errorMessage = "Your saved notes could not be opened. The file has not been changed. Check \(self.url.path) and its .backup file before restarting.\n\n\(error.localizedDescription)"
        }
    }

    private func commit(_ next: TicketArchive, localChange: Bool = false) throws {
        guard canWrite else { throw StoreError.unreadableFile }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Serialize writers across app instances, then reject stale snapshots.
        // Atomic replacement alone protects file integrity, not lost updates.
        let descriptor = Darwin.open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.concurrentChange }
        defer { flock(descriptor, LOCK_UN) }
        let previous = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard previous == lastSavedData else { throw StoreError.concurrentChange }
        if let previous {
            _ = try TicketArchive.decode(previous)
            let legacyBackup = url.appendingPathExtension("pre-icloud-backup")
            if (try? JSONDecoder().decode([TicketNote].self, from: previous)) != nil,
               !FileManager.default.fileExists(atPath: legacyBackup.path) {
                try previous.write(to: legacyBackup, options: .atomic)
            }
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        lastSavedData = data
        archive = next
        notes = next.notes
        if localChange { onLocalChange?() }
    }

    func add(_ note: TicketNote) throws {
        guard archive.records[note.id.uuidString] == nil else { throw StoreError.duplicateTicket }
        var next = archive
        next.records[note.id.uuidString] = TicketSyncRecord(note: note)
        try commit(next, localChange: true)
    }

    func update(_ note: TicketNote, originalStage: TicketStage? = nil) throws {
        guard var record = archive.records[note.id.uuidString], let current = record.note else { throw StoreError.missingTicket }
        // Prevent a stale open editor from overwriting changes received from another Mac.
        guard note.updatedAt == current.updatedAt || note == current else { throw StoreError.staleEditor }
        var edited = note
        if let originalStage, note.stage == originalStage { edited.stage = current.stage }
        edited.createdAt = current.createdAt
        edited.updatedAt = max(Date(), current.updatedAt.addingTimeInterval(0.001))
        record.change(to: edited)
        var next = archive
        next.records[note.id.uuidString] = record
        try commit(next, localChange: true)
    }

    func moveTicket(id: UUID, to stage: TicketStage) throws {
        guard var record = archive.records[id.uuidString], var note = record.note else { throw StoreError.missingTicket }
        guard note.stage != stage else { return }
        note.stage = stage
        // Keep editor revision timestamps stable for local workflow-only moves.
        record.change(to: note)
        var next = archive
        next.records[id.uuidString] = record
        try commit(next, localChange: true)
    }

    func delete(_ note: TicketNote) throws {
        guard var record = archive.records[note.id.uuidString], record.note != nil else { throw StoreError.missingTicket }
        record.change(to: nil) // A durable tombstone prevents offline devices resurrecting it.
        var next = archive
        next.records[note.id.uuidString] = record
        try commit(next, localChange: true)
    }

    func setSyncEnabled(_ enabled: Bool) throws {
        var next = archive
        next.syncEnabled = enabled
        try commit(next)
    }

    func bindCloudAccount(_ accountID: String) throws {
        if let existing = archive.cloudAccountID, existing != accountID { throw StoreError.differentAccount }
        if archive.cloudAccountID == accountID { return }
        var next = archive
        next.cloudAccountID = accountID
        try commit(next)
    }

    func applyCloudRecords(_ records: [TicketSyncRecord], accountID: String) throws {
        guard archive.cloudAccountID == accountID else { throw StoreError.differentAccount }
        var next = archive
        for record in records { next.merge(record) }
        try commit(next)
    }

    func acknowledgeCloudRecords(_ records: [TicketSyncRecord], accountID: String) throws {
        guard archive.cloudAccountID == accountID else { throw StoreError.differentAccount }
        var next = archive
        for record in records { next.acknowledge(record) }
        try commit(next)
    }

    func finishSync() throws {
        var next = archive
        next.lastSyncAt = Date()
        try commit(next)
    }

    func restoreConflict(_ conflict: TicketConflict) throws {
        var note = conflict.note
        note.id = UUID()
        note.stage = .draft
        note.updatedAt = Date()
        var next = archive
        next.records[note.id.uuidString] = TicketSyncRecord(note: note)
        next.conflicts.removeAll { $0.id == conflict.id }
        try commit(next, localChange: true)
    }

    enum StoreError: LocalizedError {
        case unreadableFile, missingTicket, duplicateTicket, differentAccount, staleEditor, concurrentChange
        var errorDescription: String? {
            switch self {
            case .unreadableFile: "Notes cannot be saved because the existing data file could not be opened. Restore your data file, then restart the app."
            case .missingTicket: "This ticket no longer exists. Copy any unsaved text, then close the editor and select another ticket."
            case .duplicateTicket: "A ticket with this identifier already exists."
            case .differentAccount: "Sync is paused because this Mac is using a different iCloud account. Sign in to the original account to resume. Your local notes have been kept."
            case .staleEditor: "This ticket changed since you opened it. Copy any unsaved text, close the editor, and reopen the ticket to see the latest version."
            case .concurrentChange: "The notes file changed outside this app or is being saved by another instance. Nothing was overwritten. Copy any unsaved text, quit all copies of Ticket Organizer, and reopen the latest version."
            }
        }
    }
}
