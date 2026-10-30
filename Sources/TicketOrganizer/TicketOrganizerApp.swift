import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers

@main
struct TicketOrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TicketStore()
    var body: some Scene {
        WindowGroup("Ticket Organizer") { ContentView(store: store).environment(\.locale, Locale(identifier: "en")) }
            .windowStyle(.titleBar)
            .defaultSize(width: 1180, height: 760)
            .commands {
                CommandGroup(after: .newItem) {
                    Button("New Ticket Note") { NotificationCenter.default.post(name: .newTicket, object: nil) }
                        .keyboardShortcut("n")
                }
                CommandGroup(replacing: .importExport) {
                    Button("Back Up Tickets…") { NotificationCenter.default.post(name: .backupTickets, object: nil) }
                    Button("Restore Tickets from Backup…") { NotificationCenter.default.post(name: .restoreTickets, object: nil) }
                }
            }
        Settings {
            CloudSyncSettingsView(store: store, sync: store.cloudSync).environment(\.locale, Locale(identifier: "en"))
        }
    }
}

extension Notification.Name {
    static let newTicket = Notification.Name("newTicket")
    static let backupTickets = Notification.Name("backupTickets")
    static let restoreTickets = Notification.Name("restoreTickets")
}

enum TicketStage: String, Codable, CaseIterable, Identifiable {
    case draft, working, approval, approved, completed
    case important = "example" // Keep the persisted value so existing tickets migrate without rewriting data.
    case closed
    var id: String { rawValue }
    var allowsIncompleteDetails: Bool { self == .draft || self == .working }
    var title: String { shortTitle }
    var shortTitle: String { switch self { case .draft: "Draft"; case .working: "Working"; case .approval: "Pending Approval"; case .approved: "Approved"; case .completed: "Completed"; case .important: "Important"; case .closed: "Closed" } }
    var color: Color { switch self { case .draft: .secondary; case .working: .blue; case .approval: .orange; case .approved: .green; case .completed: .mint; case .important: .purple; case .closed: .gray } }
}

enum Priority: String, Codable, CaseIterable, Identifiable {
    case high, medium, low
    var id: String { rawValue }
    var title: String { switch self { case .high: "High"; case .medium: "Medium"; case .low: "Low" } }
    var color: Color { switch self { case .high: .red; case .medium: .orange; case .low: .green } }
}

struct TicketNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var ritm: String
    var chg: String
    var title: String
    var body: String
    var stage: TicketStage
    var isImportant = false
    var priority: Priority
    var owner: String
    var updatedAt = Date()
    var richBody: Data? = nil
    var createdAt = Date()
    var trafficFlow: [String] = []
    var firewallZones: [[String]] = []
}

extension TicketNote {
    static func excludingClosed(_ notes: [TicketNote]) -> [TicketNote] {
        notes.filter { $0.stage != .closed }
    }

    static func importantTickets(_ notes: [TicketNote]) -> [TicketNote] {
        notes.filter { $0.isImportant || $0.stage == .important }
    }

    static func trafficFlowDescription(_ firewalls: [String]) -> String {
        let selected = firewalls.filter { !$0.isEmpty }
        return selected.isEmpty ? "" : "From " + selected.joined(separator: " to ")
    }

    static func trafficFlowSlots(_ firewalls: [String]) -> [String] {
        Array((firewalls + Array(repeating: "", count: 5)).prefix(5))
    }

    static let zoneOptions = (1...4).map { "zone \($0)" }

    static func zoneSlots(_ zones: [[String]]) -> [[String]] {
        Array((zones.map { Array($0.prefix(2)) } + Array(repeating: [], count: 5)).prefix(5))
    }

    static func togglingZone(_ zone: String, in selected: [String]) -> [String] {
        guard zoneOptions.contains(zone) else { return selected }
        var result = selected
        if let index = result.firstIndex(of: zone) { result.remove(at: index) }
        else if result.count < 2 { result.append(zone) }
        return result
    }

    static func deviceGroupPlaceholder(for firewall: String) -> String? {
        guard let index = ["FW01", "FW02", "FW03", "FW04", "FW05"].firstIndex(of: firewall) else { return nil }
        return "(device group \(index + 1))"
    }

    static func sortedByCreation(_ notes: [TicketNote], newestFirst: Bool) -> [TicketNote] {
        notes.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, ritm, chg, title, body, stage, isImportant, priority, owner, updatedAt, richBody, createdAt, trafficFlow, firewallZones
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ritm = try values.decode(String.self, forKey: .ritm)
        chg = try values.decode(String.self, forKey: .chg)
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        let storedStage = try values.decode(TicketStage.self, forKey: .stage)
        stage = storedStage
        isImportant = (try values.decodeIfPresent(Bool.self, forKey: .isImportant) ?? false) || storedStage == .important
        priority = try values.decode(Priority.self, forKey: .priority)
        owner = try values.decodeIfPresent(String.self, forKey: .owner) ?? ""
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        richBody = try values.decodeIfPresent(Data.self, forKey: .richBody)
        // Earlier versions recorded only the last modification date.
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
        trafficFlow = try values.decodeIfPresent([String].self, forKey: .trafficFlow) ?? []
        firewallZones = try values.decodeIfPresent([[String]].self, forKey: .firewallZones) ?? []
    }
}

private let createdDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

struct ContentView: View {
    @ObservedObject var store: TicketStore
    @State private var selection: TicketStage? = .draft
    @State private var selectedID: UUID?
    @State private var ticketToDelete: TicketNote?
    @State private var showDeleteConfirmation = false
    @State private var query = ""
    @State private var showNew = false
    @State private var priority: Priority? = nil
    @State private var newestFirst = false
    private var filtered: [TicketNote] {
        let stageNotes: [TicketNote]
        if let selection {
            stageNotes = selection == .important
                ? TicketNote.importantTickets(store.notes)
                : store.notes.filter { $0.stage == selection }
        } else {
            stageNotes = TicketNote.excludingClosed(store.notes)
        }
        return TicketNote.sortedByCreation(stageNotes.filter {
            (priority == nil || $0.priority == priority) &&
                (query.isEmpty || "\($0.ritm) \($0.chg) \($0.title) \($0.body)".localizedCaseInsensitiveContains(query))
        }, newestFirst: newestFirst)
    }
    private var selectedTicket: TicketNote? { filtered.first { $0.id == selectedID } }

    private func openTicket(_ id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }) else { return }
        selectedID = id
        TicketEditorWindows.shared.open(note: note, existingNotes: store.notes) { updated in
            try store.update(updated, originalStage: note.stage, originalIsImportant: note.isImportant)
        }
    }

    private func requestDeletion(_ note: TicketNote) {
        selectedID = note.id
        ticketToDelete = note
        showDeleteConfirmation = true
    }
    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, selection: $selection, showNew: $showNew, onMoved: { selectedID = $0 })
        } detail: {
            VStack(spacing: 0) {
                HStack { Spacer(); CloudSyncStatusView(sync: store.cloudSync) }.padding(.horizontal, 28).padding(.top, 12)
                HStack { VStack(alignment: .leading, spacing: 4) { Text(selection?.title ?? "Open Notes").font(.system(size: 48, weight: .bold)); Text("Keep RITM, CHG, and implementation notes together. Send them for approval when ready.").foregroundStyle(.secondary).font(.system(size: 14)) }; Spacer(); Button { showNew = true } label: { Label("New Note", systemImage: "plus") }.buttonStyle(.borderedProminent) }.padding(28)
                Divider()
                HStack { TextField("Search RITM, CHG, or notes", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300); Picker("Priority", selection: $priority) { Text("All Priorities").tag(nil as Priority?); ForEach(Priority.allCases) { Text($0.title).tag(Optional($0)) } }.frame(width: 140); Spacer(); Text("\(filtered.count) notes").foregroundStyle(.secondary).font(.caption)
                    Button(role: .destructive) {
                        if let note = selectedTicket { requestDeletion(note) }
                    } label: { Label("Delete Selected Ticket", systemImage: "trash") }
                    .disabled(selectedTicket == nil)
                }.padding(.horizontal, 28).padding(.vertical, 14)
                List(selection: $selectedID) {
                    Section {
                        ForEach(filtered) { note in
                            NoteRow(note: note).tag(note.id).contentShape(Rectangle())
                                .draggable(TicketDragItem(id: note.id)) {
                                    Label("\(note.ritm) / \(note.chg)", systemImage: "note.text")
                                        .padding(10)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                        }
                    } header: { TableHeader(newestFirst: $newestFirst) }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let note = filtered.first(where: { $0.id == id }) {
                        Button("Open Ticket") { openTicket(id) }
                        Button("Delete Ticket", role: .destructive) { requestDeletion(note) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { openTicket(id) }
                }
            }.sheet(isPresented: $showNew) { NewTicketView(existingNotes: store.notes) { try store.add($0); selection = .draft; selectedID = $0.id } }
        }
        .alert("Delete this ticket?", isPresented: $showDeleteConfirmation, presenting: ticketToDelete) { note in
            Button("Cancel", role: .cancel) { ticketToDelete = nil }
            Button("Delete", role: .destructive) {
                do {
                    try store.delete(note)
                    TicketEditorWindows.shared.close(note.id)
                    selectedID = nil
                } catch { store.errorMessage = error.localizedDescription }
                ticketToDelete = nil
            }
        } message: { note in
            Text("\(note.ritm) / \(note.chg) will be permanently deleted. This action cannot be undone.")
        }
        .onChange(of: filtered.map(\.id)) { _, ids in
            if let id = selectedID, !ids.contains(id) { selectedID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTicket)) { _ in showNew = true }
        .onReceive(NotificationCenter.default.publisher(for: .backupTickets)) { _ in exportBackup() }
        .onReceive(NotificationCenter.default.publisher(for: .restoreTickets)) { _ in restoreBackup() }
        .task { store.cloudSync.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.cloudSync.syncNow() }
        }
        .alert("Unable to Access Notes", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Ticket Organizer Backup \(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try store.exportBackup(to: destination)
            showBackupAlert(title: "Backup Saved", message: "Saved \(store.notes.count) tickets to:\n\(destination.path)")
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard !TicketEditorWindows.shared.hasOpenEditors else {
            showBackupAlert(title: "Close Ticket Editors First", message: "Close all open ticket editor windows before restoring a backup, so unsaved edits cannot overwrite the restored tickets.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let document = try TicketBackupDocument.decode(Data(contentsOf: source))
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Restore Tickets from Backup?"
            alert.informativeText = "This replaces the current ticket list with the \(document.archive.notes.count) tickets in this backup. A separate safety backup of the current data will be saved automatically before restoring. If iCloud sync is enabled, the restored tickets will sync and reconcile with that account."
            alert.addButton(withTitle: "Restore Backup")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let safetyCopy = try store.restoreBackup(from: source)
            selectedID = nil
            selection = nil
            showBackupAlert(title: "Backup Restored", message: "Restored \(document.archive.notes.count) tickets. The previous data is saved here:\n\(safetyCopy.path)")
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func showBackupAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct Sidebar: View {
    @ObservedObject var store: TicketStore
    @Binding var selection: TicketStage?
    @Binding var showNew: Bool
    var onMoved: (UUID) -> Void

    private var allNotesCountExcludingClosed: Int {
        TicketNote.excludingClosed(store.notes).count
    }

    var body: some View {
        List {
            Section {
                Button { selection = nil } label: {
                    HStack {
                        Label("Open Notes", systemImage: "tray.full")
                            .font(.system(size: 18))
                        Spacer()
                        Text("\(allNotesCountExcludingClosed)")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == nil ? .primary : .secondary)
                .help("Open Notes excludes tickets in Closed.")
            } header: {
                Text("Ticket Notes").font(.system(size: 18, weight: .semibold))
            }
            Section("Workflow") {
                ForEach(TicketStage.allCases) { stage in
                    WorkflowDropRow(store: store, stage: stage, selected: selection == stage,
                                    onSelect: { selection = stage }, onMoved: onMoved)
                }
            }
            Section {
                Button { showNew = true } label: {
                    Label("New Ticket Note", systemImage: "plus.circle").font(.system(size: 18))
                }.buttonStyle(.plain)
            }
        }.listStyle(.sidebar).navigationTitle("Ticket Organizer")
    }
}

struct TableHeader: View {
    @Binding var newestFirst: Bool
    var body: some View {
        HStack {
            Text("Ticket Number").frame(width: 180, alignment: .leading)
            Text("CHG Number").frame(width: 135, alignment: .leading)
            Button { newestFirst.toggle() } label: {
                HStack(spacing: 5) { Text("Created"); Image(systemName: newestFirst ? "chevron.down" : "chevron.up") }
            }
            .buttonStyle(.plain)
            .help(newestFirst ? "Newest first. Click for oldest first." : "Oldest first. Click for newest first.")
            .accessibilityLabel("Sort by created time")
            .accessibilityValue(newestFirst ? "Newest first" : "Oldest first")
            .frame(width: 190, alignment: .leading)
            Text("Status").frame(width: 135, alignment: .leading)
            Text("Priority").frame(width: 75, alignment: .leading)
            Text("Notes").frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 18)).foregroundStyle(.secondary)
    }
}
struct NoteRow: View {
    let note: TicketNote
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Text(note.ritm).font(.system(size: 18, design: .monospaced)).bold().foregroundStyle(.blue).lineLimit(1).help(note.ritm)
                if note.isImportant {
                    Image(systemName: "star.fill").foregroundStyle(.purple).help("Important ticket")
                }
            }.frame(width: 180, alignment: .leading)
            Text(note.chg).font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(.primary).lineLimit(1).help(note.chg).frame(width: 135, alignment: .leading)
            Text(createdDateFormatter.string(from: note.createdAt)).monospacedDigit().lineLimit(1).frame(width: 190, alignment: .leading)
            Text(note.stage.shortTitle).foregroundStyle(note.stage.color).padding(.horizontal, 8).padding(.vertical, 4).background(note.stage.color.opacity(0.12)).clipShape(Capsule()).frame(width: 135, alignment: .leading)
            Text(note.priority.title).foregroundStyle(note.priority.color).frame(width: 75, alignment: .leading)
            Text(note.title).fontWeight(.semibold).lineLimit(1).truncationMode(.tail).help(note.title).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 18)).padding(.vertical, 6)
    }
}

private func duplicateRITMMatches(_ ritm: String, among notes: [TicketNote], excluding id: UUID? = nil) -> [TicketNote] {
    let key = ritm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return [] }
    return notes.filter {
        $0.id != id && $0.ritm.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(key) == .orderedSame
    }.sorted { $0.createdAt < $1.createdAt }
}

private struct DuplicateRITMWarning: View {
    let matches: [TicketNote]

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("This RITM already exists", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                ForEach(matches) { note in
                    Text("\(note.ritm) · \(note.chg.isEmpty ? "No CHG" : note.chg) · \(note.stage.shortTitle) · \(note.title.isEmpty ? "Untitled" : note.title)")
                        .font(.caption)
                        .lineLimit(2)
                }
                Text("You can still save if this is intentional.")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SelectionFontSizeControl: View {
    @ObservedObject var controller: NoteFontSizeController

    var body: some View {
        HStack(spacing: 8) {
            Text("Selected text size:")
            Text(controller.selectionFontSize.map { "\($0) pt" } ?? "Select text first")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 64)
                .foregroundStyle(.secondary)
            Button("− Smaller") { controller.adjustSelection(by: -2) }
                .accessibilityLabel("Decrease selected text size")
                .buttonStyle(.bordered)
            Button("+ Larger") { controller.adjustSelection(by: 2) }
                .accessibilityLabel("Increase selected text size")
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .disabled(controller.selectionFontSize == nil)
        .help("Select text in the plan to change only that text's size.")
    }
}

private struct PlanEditorHeading: View {
    @ObservedObject var controller: NoteFontSizeController

    var body: some View {
        HStack {
            Text("Change, Backout, and Validation Plan").font(.headline)
            Spacer()
            Button { controller.toggleItalic() } label: { Text("I").italic().bold() }
                .help("Italic (⌘I)")
                .accessibilityLabel("Toggle italic")
            Button("Red") { controller.setTextColor(.red) }
                .foregroundStyle(.red)
                .help("Make selected text red")
                .accessibilityLabel("Make text red")
            Button("Gray") { controller.setTextColor(.gray) }
                .foregroundStyle(.gray)
                .help("Make selected text gray")
                .accessibilityLabel("Make text gray")
            Button("Default") { controller.setTextColor(.textColor) }
                .help("Restore the default text color")
                .accessibilityLabel("Restore default text color")
        }
    }
}

private struct TrafficFlowSelector: View {
    @Binding var firewalls: [String]
    @Binding var zones: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Traffic Flow")
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { position in
                    FirewallMenu(position: position, selectedFirewall: $firewalls[position - 1], selectedZones: $zones[position - 1])
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { position in
                    ZoneMenu(position: position, firewall: firewalls[position - 1], selectedZones: $zones[position - 1])
                        .frame(maxWidth: .infinity)
                }
            }
            if let firstSelected = firewalls.firstIndex(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(firewalls.indices, id: \.self) { index in
                        Text(TicketNote.deviceGroupPlaceholder(for: firewalls[index]) ?? "")
                            .font(.system(size: 24, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(firewalls.indices, id: \.self) { index in
                        Text(firewalls[index].isEmpty ? "" : "\(index == firstSelected ? "From" : "to") \(firewalls[index])")
                            .font(.system(size: 26, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TicketNote.trafficFlowDescription(firewalls))
                HStack(alignment: .top, spacing: 8) {
                    ForEach(firewalls.indices, id: \.self) { index in
                        Text(firewalls[index].isEmpty ? "" : zones[index].joined(separator: "--->"))
                            .font(.system(size: 18))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct FirewallMenu: View {
    let position: Int
    @Binding var selectedFirewall: String
    @Binding var selectedZones: [String]

    private func selectFirewall(_ firewall: String) {
        if firewall != selectedFirewall { selectedZones = [] }
        selectedFirewall = firewall
    }

    var body: some View {
        Menu {
            Button("Clear") { selectFirewall("") }
            ForEach(1...5, id: \.self) { number in
                let firewall = String(format: "FW%02d", number)
                Button(firewall) {
                    selectFirewall(firewall)
                }
            }
        } label: {
            Text(selectedFirewall.isEmpty ? "Select FW" : selectedFirewall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Traffic Flow firewall \(position)")
    }
}

private struct ZoneMenu: View {
    let position: Int
    let firewall: String
    @Binding var selectedZones: [String]

    var body: some View {
        Menu {
            Button("Clear zones") { selectedZones = [] }
                .disabled(selectedZones.isEmpty)
            ForEach(TicketNote.zoneOptions, id: \.self) { zone in
                Button {
                    selectedZones = TicketNote.togglingZone(zone, in: selectedZones)
                } label: {
                    if selectedZones.contains(zone) { Label(zone, systemImage: "checkmark") }
                    else { Text(zone) }
                }
                .disabled(selectedZones.count >= 2 && !selectedZones.contains(zone))
            }
        } label: {
            Text("Zones \(selectedZones.count)/2")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(firewall.isEmpty)
        .help("Choose up to two zones in traffic order")
        .accessibilityLabel("Zones for firewall \(position)")
        .accessibilityValue(selectedZones.isEmpty ? "None selected" : selectedZones.joined(separator: " to "))
    }
}

struct NewTicketView: View {
    @Environment(\.dismiss) private var dismiss
    let existingNotes: [TicketNote]
    var onSave: (TicketNote) throws -> Void
    @State private var ritm = ""; @State private var chg = ""; @State private var title = ""; @State private var bodyText = ""; @State private var priority: Priority = .low
    @State private var richBody: Data?
    @State private var bodyFontSize = 16
    @State private var trafficFlow = TicketNote.trafficFlowSlots([])
    @State private var firewallZones = TicketNote.zoneSlots([])
    @StateObject private var fontSizeController = NoteFontSizeController()
    @State private var createdTimeText = CreatedTimeInput.format(Date())
    @State private var saveError: String?
    private var duplicateMatches: [TicketNote] { duplicateRITMMatches(ritm, among: existingNotes) }

    private func saveNote() {
        guard let createdAt = CreatedTimeInput.parse(createdTimeText) else {
            saveError = "Enter a valid Created date and time using yyyy-MM-dd HH:mm:ss."
            return
        }
        do {
            try onSave(TicketNote(ritm: ritm.trimmingCharacters(in: .whitespacesAndNewlines), chg: chg.trimmingCharacters(in: .whitespacesAndNewlines), title: title.trimmingCharacters(in: .whitespacesAndNewlines), body: bodyText, stage: .draft, priority: priority, owner: "", richBody: richBody, createdAt: createdAt, trafficFlow: trafficFlow, firewallZones: firewallZones))
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Ticket Note").font(.title2.bold())
            Text("Only RITM is required to save a draft. CHG, title, and notes can be added later.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { LabeledContent("RITM") { TextField("RITM0767540", text: $ritm) }; LabeledContent("CHG") { TextField("CHG0197325", text: $chg) } }
            DuplicateRITMWarning(matches: duplicateMatches)
            TextField("Note title", text: $title)
            LabeledContent("Created") {
                TextField("yyyy-MM-dd HH:mm:ss", text: $createdTimeText)
                    .monospacedDigit()
                    .accessibilityLabel("Created date and time")
                Button("Now") { createdTimeText = CreatedTimeInput.format(Date()) }
            }
            Text("Format: yyyy-MM-dd HH:mm:ss · Local time")
                .font(.caption).foregroundStyle(.secondary)
            TrafficFlowSelector(firewalls: $trafficFlow, zones: $firewallZones)
            PlanEditorHeading(controller: fontSizeController)
            RichNoteEditor(text: $bodyText, richBody: $richBody, fontSize: $bodyFontSize, sizeController: fontSizeController).frame(minHeight: 150).border(Color.secondary.opacity(0.25))
            HStack { SelectionFontSizeControl(controller: fontSizeController); Spacer(); Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.title).tag($0) } }; Button("Cancel") { dismiss() }; Button("Save as Draft", action: saveNote).buttonStyle(.borderedProminent).disabled(ritm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 580)
        .alert("Unable to Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
    }
}

struct EditTicketView: View {
    var onClose: () -> Void
    var onDirtyChange: (Bool) -> Void
    let original: TicketNote
    let existingNotes: [TicketNote]
    var onSave: (TicketNote) throws -> Void
    @State private var ritm: String
    @State private var chg: String
    @State private var title: String
    @State private var bodyText: String
    @State private var stage: TicketStage
    @State private var isImportant: Bool
    @State private var priority: Priority
    @State private var richBody: Data?
    @State private var bodyFontSize: Int
    @State private var trafficFlow: [String]
    @State private var firewallZones: [[String]]
    @StateObject private var fontSizeController = NoteFontSizeController()
    @State private var createdTimeText: String
    @State private var saveError: String?

    init(note: TicketNote, existingNotes: [TicketNote], onClose: @escaping () -> Void, onDirtyChange: @escaping (Bool) -> Void, onSave: @escaping (TicketNote) throws -> Void) {
        original = note; self.existingNotes = existingNotes; self.onClose = onClose; self.onDirtyChange = onDirtyChange; self.onSave = onSave
        _ritm = State(initialValue: note.ritm); _chg = State(initialValue: note.chg); _title = State(initialValue: note.title)
        _bodyText = State(initialValue: note.body); _stage = State(initialValue: note.stage); _isImportant = State(initialValue: note.isImportant); _priority = State(initialValue: note.priority); _richBody = State(initialValue: note.richBody)
        _bodyFontSize = State(initialValue: RichNoteEditor.preferredFontSize(from: note.richBody))
        _trafficFlow = State(initialValue: TicketNote.trafficFlowSlots(note.trafficFlow))
        _firewallZones = State(initialValue: TicketNote.zoneSlots(note.firewallZones))
        _createdTimeText = State(initialValue: CreatedTimeInput.format(note.createdAt))
    }
    private var duplicateMatches: [TicketNote] { duplicateRITMMatches(ritm, among: existingNotes, excluding: original.id) }

    private func saveNote() {
        guard let createdAt = CreatedTimeInput.parse(createdTimeText) else {
            saveError = "Enter a valid Created date and time using yyyy-MM-dd HH:mm:ss."
            return
        }
        var updated = original
        updated.ritm = ritm.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.chg = chg.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = bodyText
        updated.stage = stage
        updated.isImportant = isImportant
        updated.priority = priority
        updated.richBody = richBody
        updated.createdAt = createdAt
        updated.trafficFlow = trafficFlow
        updated.firewallZones = firewallZones
        do { try onSave(updated); onClose() }
        catch { saveError = error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Ticket Note").font(.title2.bold())
            HStack {
                LabeledContent("RITM") { TextField("RITM0767540", text: $ritm).font(.system(size: 18)) }
                LabeledContent("CHG") { TextField("CHG0197325", text: $chg).font(.system(size: 18)) }
            }
            DuplicateRITMWarning(matches: duplicateMatches)
            TextField("Note title", text: $title).font(.system(size: 18))
            HStack {
                LabeledContent("Created") {
                    TextField("yyyy-MM-dd HH:mm:ss", text: $createdTimeText)
                        .monospacedDigit()
                        .accessibilityLabel("Created date and time")
                    Button("Now") { createdTimeText = CreatedTimeInput.format(Date()) }
                }
                Text("Local time")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TrafficFlowSelector(firewalls: $trafficFlow, zones: $firewallZones)
            PlanEditorHeading(controller: fontSizeController)
            RichNoteEditor(text: $bodyText, richBody: $richBody, fontSize: $bodyFontSize, sizeController: fontSizeController).frame(minHeight: 180, maxHeight: .infinity).border(Color.secondary.opacity(0.25))
            HStack {
                SelectionFontSizeControl(controller: fontSizeController)
                Spacer()
                Text("⌘B Bold · ⌘I Italic · ⌘. / ⌘+ Larger · ⌘- Smaller")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("Status", selection: $stage) { ForEach(TicketStage.allCases) { Text($0.title).tag($0) } }
                Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.title).tag($0) } }
                Toggle(isOn: $isImportant) { Label("Important ticket", systemImage: isImportant ? "star.fill" : "star") }
                    .toggleStyle(.checkbox)
                    .help("Mark this ticket as important without changing its workflow status.")
                Spacer()
            }
            HStack { Spacer(); Button("Cancel") { onClose() }.keyboardShortcut(.cancelAction); Button("Save Changes", action: saveNote).buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command).disabled(ritm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!stage.allowsIncompleteDetails && [chg, title].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })) }
        }.padding(24).frame(minWidth: 720, minHeight: 480)
        .onChange(of: [ritm, chg, title, bodyText, stage.rawValue, priority.rawValue, createdTimeText]) { _, _ in onDirtyChange(true) }
        .onChange(of: isImportant) { _, value in
            if !value && stage == .important { stage = .draft }
            onDirtyChange(true)
        }
        .onChange(of: stage) { _, value in
            if value == .important { isImportant = true }
            onDirtyChange(true)
        }
        .onChange(of: richBody) { _, _ in onDirtyChange(true) }
        .onChange(of: trafficFlow) { _, _ in onDirtyChange(true) }
        .onChange(of: firewallZones) { _, _ in onDirtyChange(true) }
        .alert("Unable to Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
    }
}

@MainActor
final class TicketEditorWindows: NSObject, NSWindowDelegate {
    static let shared = TicketEditorWindows()
    private var windows: [UUID: NSWindow] = [:]
    var hasOpenEditors: Bool { !windows.isEmpty }

    func close(_ id: UUID) {
        windows[id]?.close()
    }

    func open(note: TicketNote, existingNotes: [TicketNote], onSave: @escaping (TicketNote) throws -> Void) {
        if let existing = windows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(note.ritm) · \(note.chg) — Edit Note"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditTicketView(note: note, existingNotes: existingNotes, onClose: { [weak window] in window?.performClose(nil) }, onDirtyChange: { [weak window] dirty in window?.isDocumentEdited = dirty }, onSave: { [weak window] updated in
            try onSave(updated)
            window?.isDocumentEdited = false
        }).environment(\.locale, Locale(identifier: "en")))
        window.contentMinSize = NSSize(width: 720, height: 480)
        windows[note.id] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows.removeValue(forKey: id)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.isDocumentEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "Your changes have not been saved. Keep editing to save them, or discard them to close this window."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
