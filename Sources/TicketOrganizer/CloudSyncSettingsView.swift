import SwiftUI

struct CloudSyncSettingsView: View {
    @ObservedObject var store: TicketStore
    @ObservedObject var sync: TicketCloudSync
    @State private var operationError: String?

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Toggle("Sync with iCloud", isOn: Binding(get: { store.archive.syncEnabled }, set: {
                    do { try sync.setEnabled($0) } catch { operationError = error.localizedDescription }
                }))
                .disabled(!sync.isAvailable)
                Label(sync.status, systemImage: sync.isAvailable ? "icloud" : "icloud.slash")
                Text(sync.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Use the same Apple Account on each Mac. Sync includes note text, bold formatting, workflows, priorities, creation times, and deletions. It runs while the app is open; offline changes are queued locally.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Sync Now") { Task { await sync.syncNow() } }
                        .disabled(!sync.isAvailable || !store.archive.syncEnabled || sync.isSyncing)
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                }
                Text("Queued changes: \(store.archive.pendingRecords.count)").font(.caption)
                if let date = store.archive.lastSyncAt { Text("Last completed sync: \(date.formatted(date: .abbreviated, time: .standard))").font(.caption) }
            }
            if !store.archive.conflicts.isEmpty {
                Section("Recovered Versions") {
                    Text("When two Macs edit the same ticket offline, the latest change wins. The other version is kept here so you can recover it as a new draft.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(store.archive.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflict.note.ritm).bold()
                            Text(conflict.note.title)
                            Text(conflict.note.body).lineLimit(4).font(.caption).textSelection(.enabled)
                            Button("Restore as New Draft") {
                                do { try store.restoreConflict(conflict) } catch { operationError = error.localizedDescription }
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 540)
        .alert("iCloud Sync", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("OK") { operationError = nil }
        } message: { Text(operationError ?? "") }
    }
}

struct CloudSyncStatusView: View {
    @ObservedObject var sync: TicketCloudSync
    var body: some View {
        HStack(spacing: 6) {
            if sync.isSyncing { ProgressView().controlSize(.mini) }
            Label(sync.status, systemImage: "icloud").font(.caption).foregroundStyle(.secondary)
            SettingsLink { Text("Settings") }.font(.caption)
        }.help(sync.detail)
    }
}
