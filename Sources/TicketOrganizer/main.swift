import SwiftUI
import Foundation
import AppKit

@main
struct TicketOrganizerApp: App {
    var body: some Scene {
        WindowGroup("Ticket Organizer") { ContentView().environment(\.locale, Locale(identifier: "en")) }
            .windowStyle(.titleBar)
            .defaultSize(width: 1180, height: 760)
            .commands { CommandGroup(after: .newItem) { Button("New Ticket Note") { NotificationCenter.default.post(name: .newTicket, object: nil) }.keyboardShortcut("n") } }
    }
}

extension Notification.Name { static let newTicket = Notification.Name("newTicket") }

enum TicketStage: String, Codable, CaseIterable, Identifiable {
    case draft, approval, approved, example
    var id: String { rawValue }
    var title: String { switch self { case .draft: "Draft"; case .approval: "UCSF ticket send for approve"; case .approved: "Approved"; case .example: "UCSF ticket example" } }
    var shortTitle: String { switch self { case .draft: "Draft"; case .approval: "Pending Approval"; case .approved: "Approved"; case .example: "Examples" } }
    var color: Color { switch self { case .draft: .secondary; case .approval: .orange; case .approved: .green; case .example: .purple } }
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
    var priority: Priority
    var owner: String
    var updatedAt = Date()
    var richBody: Data? = nil
}

@MainActor
final class TicketStore: ObservableObject {
    @Published var notes: [TicketNote] = []
    private let url: URL
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TicketOrganizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("tickets.json")
        load()
    }
    func load() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([TicketNote].self, from: data) { notes = saved; return }
        notes = [
            TicketNote(ritm: "RITM0767540", chg: "CHG0197325", title: "Panorama: Add shared address objects and security rules", body: "On Panorama, Device Group: ECDC_UCSF\nOn Panorama, Device Group: QUINCY_UCSF\n\n1. OBJECTS > Addresses: Add a shared address object\n2. POLICIES > Security > Pre Rules: Add a new rule\n3. Commit and push to the QUINCY_UCSF device group", stage: .approval, priority: .high, owner: "Huang Chen"),
            TicketNote(ritm: "RITM0767221", chg: "CHG0197291", title: "Update QUINCY_UCSF device group policy", body: "Fill in source zone, source address, destination zone, service, and action.", stage: .draft, priority: .medium, owner: "Huang Chen"),
            TicketNote(ritm: "RITM0767014", chg: "CHG0197269", title: "Shared address object configuration example", body: "Validated naming conventions and device group configuration. Use as a reference for similar changes.", stage: .example, priority: .low, owner: "Jia Li"),
            TicketNote(ritm: "RITM0766903", chg: "CHG0197272", title: "Pre Rules change notes", body: "Rule creation, review, and commit are complete. Awaiting final approval.", stage: .approval, priority: .medium, owner: "Huang Chen")
        ]
    }
    func save() { if let data = try? JSONEncoder().encode(notes) { try? data.write(to: url, options: .atomic) } }
    func add(_ note: TicketNote) { notes.insert(note, at: 0); save() }
    func delete(_ note: TicketNote) { notes.removeAll { $0.id == note.id }; save() }
    func update(_ note: TicketNote) { guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }; notes[i] = note; notes[i].updatedAt = Date(); save() }
    func move(_ note: TicketNote, to stage: TicketStage) { guard let i = notes.firstIndex(of: note) else { return }; notes[i].stage = stage; notes[i].updatedAt = Date(); save() }
}

struct ContentView: View {
    @StateObject private var store = TicketStore()
    @State private var selection: TicketStage? = nil
    @State private var selectedID: UUID?
    @State private var ticketToDelete: TicketNote?
    @State private var showDeleteConfirmation = false
    @State private var query = ""
    @State private var showNew = false
    @State private var priority: Priority? = nil
    private var filtered: [TicketNote] { store.notes.filter { (selection == nil || $0.stage == selection) && (priority == nil || $0.priority == priority) && (query.isEmpty || "\($0.ritm) \($0.chg) \($0.title) \($0.body)".localizedCaseInsensitiveContains(query)) } }
    private var selectedTicket: TicketNote? { filtered.first { $0.id == selectedID } }

    private func openTicket(_ id: UUID) {
        guard let note = store.notes.first(where: { $0.id == id }) else { return }
        selectedID = id
        TicketEditorWindows.shared.open(note: note) { updated in
            store.update(updated)
        }
    }

    private func requestDeletion(_ note: TicketNote) {
        selectedID = note.id
        ticketToDelete = note
        showDeleteConfirmation = true
    }
    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, selection: $selection, showNew: $showNew)
        } detail: {
            VStack(spacing: 0) {
                HStack { VStack(alignment: .leading, spacing: 4) { Text(selection?.title ?? "All Ticket Notes").font(.system(size: 48, weight: .bold)); Text("Keep RITM, CHG, and implementation notes together. Send them for approval when ready.").foregroundStyle(.secondary).font(.system(size: 14)) }; Spacer(); Button { showNew = true } label: { Label("New Note", systemImage: "plus") }.buttonStyle(.borderedProminent) }.padding(28)
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
                        }
                    } header: { TableHeader() }
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
            }.sheet(isPresented: $showNew) { NewTicketView { store.add($0); selectedID = $0.id } }
        }
        .alert("Delete this ticket?", isPresented: $showDeleteConfirmation, presenting: ticketToDelete) { note in
            Button("Cancel", role: .cancel) { ticketToDelete = nil }
            Button("Delete", role: .destructive) {
                TicketEditorWindows.shared.close(note.id)
                store.delete(note)
                selectedID = nil
                ticketToDelete = nil
            }
        } message: { note in
            Text("\(note.ritm) / \(note.chg) will be permanently deleted. This action cannot be undone.")
        }
        .onChange(of: filtered.map(\.id)) { _, ids in
            if let id = selectedID, !ids.contains(id) { selectedID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTicket)) { _ in showNew = true }
    }
}

struct Sidebar: View {
    @ObservedObject var store: TicketStore; @Binding var selection: TicketStage?; @Binding var showNew: Bool
    var body: some View { List { Section { Button { selection = nil } label: { Label("All Notes", systemImage: "tray.full").font(.system(size: 14)) }.buttonStyle(.plain).foregroundStyle(selection == nil ? .primary : .secondary) } header: { Text("Ticket Notes").font(.system(size: 14, weight: .semibold)) }; Section("Workflow") { ForEach(TicketStage.allCases) { stage in Button { selection = stage } label: { HStack { Image(systemName: stage == .draft ? "note.text" : stage == .approval ? "paperplane" : stage == .approved ? "checkmark.circle" : "star") .foregroundStyle(stage.color); Text(stage.shortTitle).font(.system(size: 14)); Spacer(); Text("\(store.notes.filter { $0.stage == stage }.count)").foregroundStyle(.secondary).font(.system(size: 12)) }.contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(selection == stage ? .primary : .secondary) } }; Section { Button { showNew = true } label: { Label("New Ticket Note", systemImage: "plus.circle").font(.system(size: 14)) }.buttonStyle(.plain) } } .listStyle(.sidebar).navigationTitle("Ticket Organizer") }
}

struct TableHeader: View { var body: some View { HStack { Text("Ticket Numbers").frame(width: 180, alignment: .leading); Text("Status").frame(width: 135, alignment: .leading); Text("Priority").frame(width: 75, alignment: .leading); Text("Notes").frame(maxWidth: .infinity, alignment: .leading) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8) } }
struct NoteRow: View {
    let note: TicketNote
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text(note.ritm).font(.system(size: 16, design: .monospaced)).bold(); Text(note.chg).font(.system(size: 16, design: .monospaced)).foregroundStyle(.secondary) }.frame(width: 180, alignment: .leading)
            Text(note.stage.shortTitle).foregroundStyle(note.stage.color).padding(.horizontal, 8).padding(.vertical, 4).background(note.stage.color.opacity(0.12)).clipShape(Capsule()).frame(width: 135, alignment: .leading)
            Text(note.priority.title).foregroundStyle(note.priority.color).frame(width: 75, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) { Text(note.title).font(.system(size: 16, weight: .semibold)); Text(note.body.replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).font(.system(size: 14)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
}

struct DetailView: View { let note: TicketNote; @ObservedObject var store: TicketStore; var onDelete: () -> Void; @State private var confirmDelete = false; var body: some View { VStack(alignment: .leading, spacing: 18) { Text("Ticket Details").font(.headline); Text("\(note.ritm), \(note.chg)").font(.system(.title3, design: .monospaced)).bold(); Divider(); Text(note.title).font(.title2.bold()); Text(note.body).textSelection(.enabled); Spacer(); HStack { Button("Move to Draft") { store.move(note, to: .draft) }.disabled(note.stage == .draft); Button("Send for Approval") { store.move(note, to: .approval) }.disabled(note.stage == .approval); Button("Save as Example") { store.move(note, to: .example) }.disabled(note.stage == .example); Spacer(); Button("Delete Ticket", role: .destructive) { confirmDelete = true } }.buttonStyle(.borderedProminent) }.padding(24).frame(minWidth: 320, alignment: .leading).alert("Delete this ticket?", isPresented: $confirmDelete) { Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { onDelete() } } message: { Text("This will permanently remove the ticket from your list and local storage. This action cannot be undone.") } } }

struct NewTicketView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (TicketNote) -> Void
    @State private var ritm = ""; @State private var chg = ""; @State private var title = ""; @State private var bodyText = ""; @State private var priority: Priority = .medium
    @State private var richBody: Data?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Ticket Note").font(.title2.bold())
            HStack { LabeledContent("RITM") { TextField("RITM0767540", text: $ritm) }; LabeledContent("CHG") { TextField("CHG0197325", text: $chg) } }
            TextField("Note title", text: $title)
            RichNoteEditor(text: $bodyText, richBody: $richBody).frame(minHeight: 150).border(Color.secondary.opacity(0.25))
            HStack { Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.title).tag($0) } }; Spacer(); Button("Cancel") { dismiss() }; Button("Save as Draft") { onSave(TicketNote(ritm: ritm, chg: chg, title: title, body: bodyText, stage: .draft, priority: priority, owner: "", richBody: richBody)); dismiss() }.buttonStyle(.borderedProminent).disabled(ritm.isEmpty || chg.isEmpty || title.isEmpty) }
        }.padding(24).frame(width: 580)
    }
}

struct EditTicketView: View {
    var onClose: () -> Void
    let original: TicketNote
    var onSave: (TicketNote) -> Void
    @State private var ritm: String
    @State private var chg: String
    @State private var title: String
    @State private var bodyText: String
    @State private var stage: TicketStage
    @State private var priority: Priority
    @State private var richBody: Data?

    init(note: TicketNote, onClose: @escaping () -> Void, onSave: @escaping (TicketNote) -> Void) {
        original = note; self.onClose = onClose; self.onSave = onSave
        _ritm = State(initialValue: note.ritm); _chg = State(initialValue: note.chg); _title = State(initialValue: note.title)
        _bodyText = State(initialValue: note.body); _stage = State(initialValue: note.stage); _priority = State(initialValue: note.priority); _richBody = State(initialValue: note.richBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Ticket Note").font(.title2.bold())
            HStack { LabeledContent("RITM") { TextField("RITM0767540", text: $ritm) }; LabeledContent("CHG") { TextField("CHG0197325", text: $chg) } }
            TextField("Note title", text: $title)
            RichNoteEditor(text: $bodyText, richBody: $richBody).frame(minHeight: 180, maxHeight: .infinity).border(Color.secondary.opacity(0.25))
            HStack { Picker("Status", selection: $stage) { ForEach(TicketStage.allCases) { Text($0.title).tag($0) } }; Picker("Priority", selection: $priority) { ForEach(Priority.allCases) { Text($0.title).tag($0) } }; Spacer(); Text("⌘B Bold").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Cancel") { onClose() }.keyboardShortcut(.cancelAction); Button("Save Changes") { var updated = original; updated.ritm = ritm; updated.chg = chg; updated.title = title; updated.body = bodyText; updated.stage = stage; updated.priority = priority; updated.richBody = richBody; onSave(updated); onClose() }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command).disabled(ritm.isEmpty || chg.isEmpty || title.isEmpty) }
        }.padding(24).frame(minWidth: 720, minHeight: 480)
    }
}

@MainActor
final class TicketEditorWindows: NSObject, NSWindowDelegate {
    static let shared = TicketEditorWindows()
    private var windows: [UUID: NSWindow] = [:]

    func close(_ id: UUID) {
        windows[id]?.close()
    }

    func open(note: TicketNote, onSave: @escaping (TicketNote) -> Void) {
        if let existing = windows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(note.ritm) · \(note.chg) — Edit Note"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditTicketView(note: note, onClose: { [weak window] in window?.close() }, onSave: onSave).environment(\.locale, Locale(identifier: "en")))
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
}
