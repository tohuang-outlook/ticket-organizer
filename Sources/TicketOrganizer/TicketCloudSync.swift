import Foundation
import Combine
import CloudKit

@MainActor
final class TicketCloudSync: ObservableObject {
    @Published private(set) var status = "iCloud Off"
    @Published private(set) var detail = "Notes are saved on this Mac."
    @Published private(set) var isSyncing = false
    private weak var store: TicketStore?
    private var transport: TicketCloudTransport?
    private let automatic: Bool
    private let injected: Bool
    private var timer: Task<Void, Never>?
    private var scheduled: Task<Void, Never>?
    private var accountObserver: NSObjectProtocol?
    private var generation = 0
    private var retryNotBefore = Date.distantPast

    var isAvailable: Bool { injected || TicketCloudConfiguration.isAvailable }

    init(store: TicketStore, transport: TicketCloudTransport? = nil, automatic: Bool = true) {
        self.store = store
        self.transport = transport
        self.automatic = automatic
        injected = transport != nil
        store.onLocalChange = { [weak self] in self?.schedule() }
        if !isAvailable {
            status = "iCloud Setup Required"
            detail = "iCloud is not enabled for this version of the app. Your notes continue to save on this Mac. Install an iCloud-enabled signed version to use sync."
        }
        if automatic {
            accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.generation += 1
                    self?.scheduled?.cancel()
                    self?.status = "Checking iCloud Account"
                    await self?.syncNow()
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        scheduled?.cancel()
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    func start() {
        guard automatic, timer == nil else { return }
        timer = Task { [weak self] in
            await self?.syncNow()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await self?.syncNow()
            }
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard let store else { return }
        if enabled && !isAvailable { throw SyncError.configurationRequired }
        try store.setSyncEnabled(enabled)
        generation += 1
        scheduled?.cancel()
        if enabled { schedule() }
        else { status = "iCloud Off"; detail = "Notes remain on this Mac and in iCloud. Changes are queued locally until sync is enabled again." }
    }

    private func schedule() {
        guard automatic, store?.archive.syncEnabled == true, isAvailable else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await self?.syncNow()
        }
    }

    private func check(_ cycle: Int) throws {
        guard generation == cycle, store?.archive.syncEnabled == true, !Task.isCancelled else { throw CancellationError() }
    }

    func syncNow() async {
        guard let store, store.archive.syncEnabled, isAvailable, !isSyncing, Date() >= retryNotBefore else { return }
        if transport == nil { transport = CloudKitTicketTransport() }
        guard let transport else { return }
        isSyncing = true
        status = "Syncing with iCloud"
        detail = "Your notes are saved locally while changes are synchronized."
        let cycle = generation
        defer { isSyncing = false }
        do {
            let accountID = try await transport.accountID()
            try check(cycle)
            try store.bindCloudAccount(accountID)
            let records = try await transport.fetchRecords()
            try check(cycle)
            guard try await transport.accountID() == accountID else { throw TicketStore.StoreError.differentAccount }
            try check(cycle)
            try store.applyCloudRecords(records, accountID: accountID)
            // Bounded batches also allow UI edits between network requests.
            for _ in 0..<20 {
                let pending = Array(store.archive.pendingRecords.prefix(50))
                if pending.isEmpty { break }
                let results = try await transport.saveRecords(pending)
                try check(cycle)
                guard try await transport.accountID() == accountID else { throw TicketStore.StoreError.differentAccount }
                try check(cycle)
                var acknowledged: [TicketSyncRecord] = []
                var conflicts: [TicketSyncRecord] = []
                var failures: [Error] = []
                for result in results {
                    switch result {
                    case .saved(let record): acknowledged.append(record)
                    case .conflict(let record): conflicts.append(record)
                    case .failure(let error): failures.append(error)
                    }
                }
                try store.acknowledgeCloudRecords(acknowledged, accountID: accountID)
                try store.applyCloudRecords(conflicts, accountID: accountID)
                if let failure = failures.first { throw failure }
                if !conflicts.isEmpty || acknowledged.count != pending.count {
                    status = "Changes Queued"
                    detail = "iCloud changed during this sync. Remaining changes will be retried."
                    return
                }
            }
            if store.archive.pendingRecords.isEmpty {
                try store.finishSync()
                status = "iCloud Up to Date"
                detail = "Notes are synchronized with the private database of your iCloud account."
            } else {
                status = "Changes Queued"
                detail = "More changes remain and will sync automatically while this app is open."
            }
        } catch is CancellationError {
            // Disabling sync or changing accounts invalidates all in-flight responses.
        } catch {
            let retry = (error as? CKError)?.retryAfterSeconds ?? 60
            retryNotBefore = Date().addingTimeInterval(max(60, retry))
            status = "iCloud Sync Paused"
            detail = error.localizedDescription + " Your local changes are kept and will be retried."
        }
    }

    enum SyncError: LocalizedError {
        case configurationRequired, remote(String)
        var errorDescription: String? {
            switch self {
            case .configurationRequired: "iCloud sync requires an Apple-signed build configured for this app's CloudKit container."
            case .remote(let message): message
            }
        }
    }
}
