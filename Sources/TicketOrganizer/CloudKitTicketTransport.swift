import Foundation
import CloudKit
import Security

enum TicketCloudSaveResult {
    case saved(TicketSyncRecord)
    case conflict(TicketSyncRecord)
    case failure(Error)
}

@MainActor
protocol TicketCloudTransport {
    func accountID() async throws -> String
    func fetchRecords() async throws -> [TicketSyncRecord]
    func saveRecords(_ records: [TicketSyncRecord]) async throws -> [TicketCloudSaveResult]
}

enum TicketCloudConfiguration {
    static let containerID = "iCloud.com.tohuang.ticket-organizer"
    static var isAvailable: Bool {
        // Read the actual code signature, not a user preference or an Info.plist claim.
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              let services = entitlements["com.apple.developer.icloud-services"] as? [String] else { return false }
        return containers.contains(containerID) && services.contains("CloudKit") && Bundle.main.url(forResource: "embedded", withExtension: "provisionprofile") != nil
    }
}

@MainActor
final class CloudKitTicketTransport: TicketCloudTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private let zone = CKRecordZone.ID(zoneName: "TicketOrganizer", ownerName: CKCurrentUserDefaultName)

    init() {
        container = CKContainer(identifier: TicketCloudConfiguration.containerID)
        database = container.privateCloudDatabase
    }

    func accountID() async throws -> String {
        guard try await container.accountStatus() == .available else { throw CloudError.noAccount }
        return try await container.userRecordID().recordName
    }

    func fetchRecords() async throws -> [TicketSyncRecord] {
        _ = try await database.save(CKRecordZone(zoneID: zone))
        let query = CKQuery(recordType: "TicketChange", predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, inZoneWith: zone, desiredKeys: nil, resultsLimit: 100)
        var result: [TicketSyncRecord] = []
        while true {
            for (_, record) in page.matchResults { result.append(try decode(record.get())) }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: nil, resultsLimit: 100)
        }
        return result
    }

    func saveRecords(_ records: [TicketSyncRecord]) async throws -> [TicketCloudSaveResult] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TicketCloud-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pending = Array(records.prefix(50))
        let cloudRecords = try pending.map { item in
            let recordID = CKRecord.ID(recordName: item.id.uuidString, zoneID: zone)
            let record: CKRecord
            if let data = item.serverFields {
                let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
                decoder.requiresSecureCoding = true
                defer { decoder.finishDecoding() }
                guard let restored = CKRecord(coder: decoder), restored.recordID == recordID else { throw CloudError.invalidRecord }
                record = restored
            } else { record = CKRecord(recordType: "TicketChange", recordID: recordID) }
            let file = directory.appendingPathComponent(item.id.uuidString + ".json")
            try JSONEncoder().encode(WireRecord(item)).write(to: file, options: .atomic)
            record["payload"] = CKAsset(fileURL: file)
            return record
        }
        let changes = try await database.modifyRecords(saving: cloudRecords, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        var results: [TicketCloudSaveResult] = []
        for item in pending {
            let id = CKRecord.ID(recordName: item.id.uuidString, zoneID: zone)
            guard let result = changes.saveResults[id] else {
                results.append(.failure(CloudError.missingAcknowledgment))
                continue
            }
            switch result {
            case .success(let record):
                var acknowledged = item
                acknowledged.serverFields = systemFields(record)
                results.append(.saved(acknowledged))
            case .failure(let error):
                if let cloud = error as? CKError, cloud.code == .serverRecordChanged {
                    // Fetch the complete asset; the conflict error may contain only metadata.
                    let server = try await database.record(for: id)
                    results.append(.conflict(try decode(server)))
                } else {
                    results.append(.failure(error))
                }
            }
        }
        return results
    }

    private func decode(_ record: CKRecord) throws -> TicketSyncRecord {
        guard record.recordType == "TicketChange", record.recordID.zoneID == zone,
              let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw CloudError.invalidRecord }
        let wire = try JSONDecoder().decode(WireRecord.self, from: Data(contentsOf: url))
        guard wire.schemaVersion == 1, wire.id.uuidString == record.recordID.recordName,
              wire.note == nil || wire.note?.id == wire.id else { throw CloudError.invalidRecord }
        return TicketSyncRecord(id: wire.id, note: wire.note, revision: wire.revision, changedAt: wire.changedAt,
                                uploadedRevision: wire.revision, serverFields: systemFields(record))
    }

    private func systemFields(_ record: CKRecord) -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }

    private struct WireRecord: Codable {
        var schemaVersion = 1
        let id: UUID
        let note: TicketNote?
        let revision: UUID
        let changedAt: Date
        init(_ record: TicketSyncRecord) {
            id = record.id; note = record.note; revision = record.revision; changedAt = record.changedAt
        }
    }

    enum CloudError: LocalizedError {
        case noAccount, invalidRecord, missingAcknowledgment
        var errorDescription: String? {
            switch self {
            case .noAccount: "Sign in to iCloud in System Settings to sync. Your notes remain saved on this Mac."
            case .invalidRecord: "An iCloud record could not be read safely. Sync is paused; your local notes are unchanged."
            case .missingAcknowledgment: "iCloud did not acknowledge a queued change. It will be retried."
            }
        }
    }
}
