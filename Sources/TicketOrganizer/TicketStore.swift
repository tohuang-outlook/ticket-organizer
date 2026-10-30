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
    var firewalls: [FirewallDefinition] { archive.firewalls ?? FirewallDefinition.placeholders }

    func saveFirewall(_ firewall: FirewallDefinition, isNew: Bool) throws {
        var item = firewall
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.deviceGroup = item.deviceGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        item.zones = item.zones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !item.id.isEmpty, !item.name.isEmpty else { throw FirewallError.nameRequired }
        guard Set(item.zones.map { $0.lowercased() }).count == item.zones.count else { throw FirewallError.duplicateZone }
        var entries = firewalls
        guard !entries.contains(where: { $0.id != item.id && $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) else { throw FirewallError.duplicateName }
        if isNew {
            guard !entries.contains(where: { $0.id.caseInsensitiveCompare(item.id) == .orderedSame }) else { throw FirewallError.duplicateName }
            entries.append(item)
        } else if let index = entries.firstIndex(where: { $0.id == item.id }) { entries[index] = item }
        else { throw FirewallError.missingFirewall }
        var next = archive
        next.firewalls = entries
        try commit(next)
    }

    func setFirewallActive(id: String, isActive: Bool) throws {
        guard var firewall = firewalls.first(where: { $0.id == id }) else { throw FirewallError.missingFirewall }
        guard firewall.isActive != isActive else { return }
        firewall.isActive = isActive
        try saveFirewall(firewall, isNew: false)
    }

    enum FirewallError: LocalizedError {
        case nameRequired, duplicateName, duplicateZone, missingFirewall
        var errorDescription: String? {
            switch self {
            case .nameRequired: "Enter a firewall name."
            case .duplicateName: "This firewall name is already in use or reserved by an existing firewall."
            case .duplicateZone: "Each zone must have a unique name."
            case .missingFirewall: "This firewall is no longer available. Reopen Firewall Settings and try again."
            }
        }
    }

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

    func update(_ note: TicketNote, originalStage: TicketStage? = nil, originalIsImportant: Bool? = nil) throws {
        guard var record = archive.records[note.id.uuidString], let current = record.note else { throw StoreError.missingTicket }
        // Prevent a stale open editor from overwriting changes received from another Mac.
        guard note.updatedAt == current.updatedAt || note == current else { throw StoreError.staleEditor }
        var edited = note
        if let originalStage, note.stage == originalStage { edited.stage = current.stage }
        if let originalIsImportant, note.isImportant == originalIsImportant { edited.isImportant = current.isImportant }
        edited.updatedAt = max(Date(), current.updatedAt.addingTimeInterval(0.001))
        record.change(to: edited)
        var next = archive
        next.records[note.id.uuidString] = record
        try commit(next, localChange: true)
    }

    func moveTicket(id: UUID, to stage: TicketStage) throws {
        guard var record = archive.records[id.uuidString], var note = record.note else { throw StoreError.missingTicket }
        if stage == .important {
            guard !note.isImportant else { return }
            note.isImportant = true
        } else {
            guard note.stage != stage else { return }
            note.stage = stage
        }
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

    func exportBackup(to destination: URL) throws {
        guard canWrite else { throw StoreError.unreadableFile }
        let protectedFiles = [url, url.appendingPathExtension("backup"), url.appendingPathExtension("pre-icloud-backup")]
        guard !protectedFiles.contains(where: { $0.standardizedFileURL == destination.standardizedFileURL }) else {
            throw StoreError.backupDestinationProtected
        }
        let currentData = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard currentData == lastSavedData else { throw StoreError.concurrentChange }
        var backupArchive = archive
        if backupArchive.firewalls == nil { backupArchive.firewalls = FirewallDefinition.placeholders }
        let document = TicketBackupDocument(archive: backupArchive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    @discardableResult
    func restoreBackup(from source: URL) throws -> URL {
        let backup = try TicketBackupDocument.decode(Data(contentsOf: source))
        if let currentAccount = archive.cloudAccountID, currentAccount != backup.archive.cloudAccountID {
            throw StoreError.backupAccountMismatch
        }

        // Keep a restorable pre-restore snapshot before changing the working archive.
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safetyCopy = url.deletingLastPathComponent().appendingPathComponent("TicketOrganizer-before-restore-\(timestamp)-\(UUID().uuidString).json")
        try exportBackup(to: safetyCopy)

        // Convert the imported snapshot into new local revisions so active iCloud sync can
        // converge toward the restored snapshot. A tombstoned ID gets a new ID to preserve
        // the store's delete-wins rule and prevent deleted tickets from being resurrected.
        var next = archive
        if let firewalls = backup.archive.firewalls { next.firewalls = firewalls }
        if next.records.isEmpty && next.cloudAccountID == nil {
            next.cloudAccountID = backup.archive.cloudAccountID
            next.syncEnabled = backup.archive.syncEnabled
        }
        let backupNotes = backup.archive.notes
        let backupIDs = Set(backupNotes.map(\.id))
        for key in Array(next.records.keys) {
            guard var record = next.records[key], let note = record.note,
                  !backupIDs.contains(note.id) else { continue }
            record.change(to: nil)
            next.records[key] = record
        }
        for var note in backupNotes {
            if var current = next.records[note.id.uuidString], let existingNote = current.note {
                if existingNote == note { continue }
                note.updatedAt = max(Date(), existingNote.updatedAt.addingTimeInterval(0.001))
                current.change(to: note)
                next.records[note.id.uuidString] = current
            } else {
                if next.records[note.id.uuidString] != nil { note.id = UUID() }
                note.updatedAt = max(Date(), note.updatedAt)
                next.records[note.id.uuidString] = TicketSyncRecord(note: note)
            }
        }
        try commit(next, localChange: true)
        return safetyCopy
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
        case unreadableFile, missingTicket, duplicateTicket, differentAccount, staleEditor, concurrentChange, backupAccountMismatch, backupDestinationProtected
        var errorDescription: String? {
            switch self {
            case .unreadableFile: "Notes cannot be saved because the existing data file could not be opened. Restore your data file, then restart the app."
            case .missingTicket: "This ticket no longer exists. Copy any unsaved text, then close the editor and select another ticket."
            case .duplicateTicket: "A ticket with this identifier already exists."
            case .differentAccount: "Sync is paused because this Mac is using a different iCloud account. Sign in to the original account to resume. Your local notes have been kept."
            case .staleEditor: "This ticket changed since you opened it. Copy any unsaved text, close the editor, and reopen the ticket to see the latest version."
            case .concurrentChange: "The notes file changed outside this app or is being saved by another instance. Nothing was overwritten. Copy any unsaved text, quit all copies of Ticket Organizer, and reopen the latest version."
            case .backupAccountMismatch: "This backup is linked to a different iCloud account than this Mac. No tickets were changed. Sign in to the matching account or use a backup from this account."
            case .backupDestinationProtected: "Choose a different backup location. Ticket Organizer will not overwrite its live data or automatic backups."
            }
        }
    }
}
