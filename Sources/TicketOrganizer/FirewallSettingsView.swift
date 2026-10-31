import SwiftUI

private struct FirewallEditRequest: Identifiable {
    let id = UUID()
    let firewall: FirewallDefinition?
    let showCLI: Bool
}

struct FirewallSettingsView: View {
    @ObservedObject var store: TicketStore
    @State private var request: FirewallEditRequest?
    @State private var firewallToDelete: FirewallDefinition?
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Firewall Settings").font(.title2.bold())
                Spacer()
                Button("Import CLI Output") { request = FirewallEditRequest(firewall: nil, showCLI: true) }
                Button("Add Firewall") { request = FirewallEditRequest(firewall: nil, showCLI: false) }
                    .buttonStyle(.borderedProminent)
            }
            Text("Configure names, device groups, and available zones. Existing ticket selections stay linked when a firewall is renamed. Existing zone selections are kept when zones change.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(store.firewalls) { firewall in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(firewall.name).fontWeight(.semibold)
                                if !firewall.isActive { Text("Inactive").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(firewall.deviceGroup.isEmpty ? "No device group" : firewall.deviceGroup)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(firewall.zones.isEmpty ? "No zones" : firewall.zones.joined(separator: ", "))
                                .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { request = FirewallEditRequest(firewall: firewall, showCLI: false) }
                        Button("Delete", role: .destructive) { firewallToDelete = firewall }
                    }
                    .padding(.vertical, 3)
                }
            }
            Text("Firewall settings are stored on this Mac and included in ticket backups. They do not currently sync through iCloud.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 650, height: 540)
        .sheet(item: $request) { request in
            FirewallEditorView(store: store, firewall: request.firewall, startWithCLI: request.showCLI)
        }
        .confirmationDialog("Delete Firewall?", isPresented: Binding(get: { firewallToDelete != nil }, set: { if !$0 { firewallToDelete = nil } }), presenting: firewallToDelete) { firewall in
            Button("Delete \(firewall.name)", role: .destructive) {
                do { try store.deleteFirewall(id: firewall.id) }
                catch { deleteError = error.localizedDescription }
                firewallToDelete = nil
            }
            Button("Cancel", role: .cancel) { firewallToDelete = nil }
        } message: { firewall in
            Text("Delete \(firewall.name) from Firewall Settings? Firewalls used by tickets cannot be deleted; deactivate them instead.")
        }
        .alert("Unable to Delete Firewall", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}

private struct FirewallEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TicketStore
    let original: FirewallDefinition?
    @State private var name: String
    @State private var deviceGroup: String
    @State private var zoneText: String
    @State private var isActive: Bool
    @State private var showCLI: Bool
    @State private var cliText = ""
    @State private var cliMessage = ""
    @State private var saveError: String?

    init(store: TicketStore, firewall: FirewallDefinition?, startWithCLI: Bool) {
        self.store = store
        original = firewall
        _name = State(initialValue: firewall?.name ?? "")
        _deviceGroup = State(initialValue: firewall?.deviceGroup ?? "")
        _zoneText = State(initialValue: firewall?.zones.joined(separator: "\n") ?? "")
        _isActive = State(initialValue: firewall?.isActive ?? true)
        _showCLI = State(initialValue: startWithCLI)
    }

    private func extractCLI() {
        let result = FirewallCLIParser.parse(cliText)
        guard !result.hasMultipleHostnames else {
            cliMessage = "Multiple hostnames found. Paste output from one firewall at a time."
            return
        }
        guard result.hostname != nil || !result.zones.isEmpty else {
            cliMessage = "No supported hostname or zone lines found. Enter the fields manually or paste PAN-OS output."
            return
        }
        if let hostname = result.hostname { name = hostname }
        if !result.zones.isEmpty { zoneText = result.zones.joined(separator: "\n") }
        cliMessage = result.zonesMayBeTruncated
            ? "Interface tables may truncate zone names. Verify and complete every zone name before saving; enter the device group manually."
            : "Fields extracted. Review the firewall name and zones, and enter the device group before saving."
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firewall = FirewallDefinition(id: original?.id ?? cleanName, name: cleanName,
                                          deviceGroup: deviceGroup, zones: zoneText.components(separatedBy: .newlines),
                                          isActive: isActive)
        do {
            try store.saveFirewall(firewall, isNew: original == nil)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original == nil ? "Add Firewall" : "Edit Firewall").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("Firewall Name"); TextField("Firewall name", text: $name) }
                GridRow { Text("Device Group"); TextField("Device group", text: $deviceGroup) }
            }
            Toggle("Active", isOn: $isActive)
                .help("Inactive firewalls remain visible in existing tickets but are not offered for new selections.")
            Text("Zones — one per line").font(.headline)
            TextEditor(text: $zoneText).font(.body).frame(minHeight: 80, maxHeight: 120).border(Color.secondary.opacity(0.25))
            DisclosureGroup("Import from CLI output", isExpanded: $showCLI) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste PAN-OS show interface all, hostname, or set zone output from one firewall. Review the extracted fields before saving.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $cliText).font(.system(.caption, design: .monospaced)).frame(height: 100).border(Color.secondary.opacity(0.25))
                    HStack {
                        Button("Extract Fields") { extractCLI() }.disabled(cliText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text(cliMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 6)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Firewall") { save() }.buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: showCLI ? 590 : 380)
        .alert("Unable to Save Firewall", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }
}
