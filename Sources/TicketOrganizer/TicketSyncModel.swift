import Foundation

struct TicketSyncRecord: Codable, Equatable {
    var id: UUID
    var note: TicketNote?
    var revision: UUID
    var changedAt: Date
    var uploadedRevision: UUID?
    var serverFields: Data?

    var isPending: Bool { revision != uploadedRevision }

    init(id: UUID, note: TicketNote?, revision: UUID, changedAt: Date, uploadedRevision: UUID?, serverFields: Data?) {
        self.id = id; self.note = note; self.revision = revision; self.changedAt = changedAt
        self.uploadedRevision = uploadedRevision; self.serverFields = serverFields
    }

    init(note: TicketNote) {
        id = note.id
        self.note = note
        revision = UUID()
        changedAt = note.updatedAt
    }

    mutating func change(to note: TicketNote?) {
        self.note = note
        revision = UUID()
        changedAt = max(Date(), changedAt.addingTimeInterval(0.001))
    }

    func isNewer(than other: TicketSyncRecord) -> Bool {
        changedAt == other.changedAt ? revision.uuidString > other.revision.uuidString : changedAt > other.changedAt
    }
}

struct TicketConflict: Codable, Identifiable {
    var id: UUID // The losing revision, used to avoid duplicate recovery copies.
    var note: TicketNote
}

struct TicketArchive: Codable {
    var schemaVersion = 2
    var records: [String: TicketSyncRecord] = [:]
    var conflicts: [TicketConflict] = []
    var syncEnabled = false
    var cloudAccountID: String?
    var lastSyncAt: Date?

    var notes: [TicketNote] { records.values.compactMap(\.note) }
    var pendingRecords: [TicketSyncRecord] { records.values.filter(\.isPending) }

    static func decode(_ data: Data) throws -> TicketArchive {
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode([TicketNote].self, from: data) {
            var archive = TicketArchive()
            for note in legacy {
                guard archive.records[note.id.uuidString] == nil else { throw ArchiveError.invalidData }
                archive.records[note.id.uuidString] = TicketSyncRecord(note: note)
            }
            return archive
        }
        let archive = try decoder.decode(TicketArchive.self, from: data)
        guard archive.schemaVersion == 2,
              archive.records.allSatisfy({ key, value in key == value.id.uuidString && (value.note == nil || value.note?.id == value.id) }) else { throw ArchiveError.invalidData }
        return archive
    }

    mutating func merge(_ remote: TicketSyncRecord) {
        let key = remote.id.uuidString
        guard var local = records[key] else {
            var accepted = remote
            accepted.uploadedRevision = remote.revision
            records[key] = accepted
            return
        }
        if local.revision == remote.revision {
            local.uploadedRevision = remote.revision
            local.serverFields = remote.serverFields
            records[key] = local
            return
        }
        // A deletion is final for an identifier. Recovery creates a fresh identifier.
        let remoteWins: Bool
        if remote.note == nil && local.note != nil { remoteWins = true }
        else if local.note == nil && remote.note != nil { remoteWins = false }
        else { remoteWins = remote.isNewer(than: local) }
        let concurrent = local.isPending && remote.revision != local.uploadedRevision
        if concurrent {
            let losing = remoteWins ? local : remote
            if let note = losing.note, !conflicts.contains(where: { $0.id == losing.revision }) {
                conflicts.append(TicketConflict(id: losing.revision, note: note))
            }
        }
        if remoteWins {
            var accepted = remote
            accepted.uploadedRevision = remote.revision
            records[key] = accepted
        } else {
            local.serverFields = remote.serverFields
            local.uploadedRevision = remote.revision
            records[key] = local
        }
    }

    mutating func acknowledge(_ uploaded: TicketSyncRecord) {
        guard var current = records[uploaded.id.uuidString] else { return }
        current.serverFields = uploaded.serverFields
        current.uploadedRevision = uploaded.revision
        records[uploaded.id.uuidString] = current
    }

    enum ArchiveError: LocalizedError {
        case invalidData
        var errorDescription: String? { "The notes file uses an unsupported format or contains invalid records. It has not been changed." }
    }
}

struct TicketBackupDocument: Codable {
    static let currentFormat = "com.tohuang.ticket-organizer.backup"
    static let currentVersion = 1

    let format: String
    let version: Int
    let exportedAt: Date
    let archive: TicketArchive

    init(archive: TicketArchive, exportedAt: Date = Date()) {
        self.format = Self.currentFormat
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.archive = archive
    }

    static func decode(_ data: Data) throws -> TicketBackupDocument {
        let document = try JSONDecoder().decode(TicketBackupDocument.self, from: data)
        guard document.format == currentFormat,
              document.version == currentVersion,
              document.archive.schemaVersion == 2,
              document.archive.records.allSatisfy({ key, record in
                  key == record.id.uuidString && (record.note == nil || record.note?.id == record.id)
              }) else { throw BackupError.invalidBackup }
        return document
    }

    enum BackupError: LocalizedError {
        case invalidBackup
        var errorDescription: String? {
            switch self {
            case .invalidBackup: "This is not a supported Ticket Organizer backup. No tickets were changed."
            }
        }
    }
}
