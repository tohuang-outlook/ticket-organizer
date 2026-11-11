import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TrafficLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TicketStore
    @State private var address = ""
    @State private var importRequest: ImportRequest?
    @State private var error: String?

    private var records: [NetworkRecord] { (try? store.networkRecords()) ?? [] }
    private var results: [NetworkRecord]? { NetworkLookup.matches(address, records: records) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Traffic Lookup").font(.title2.bold())
                Spacer()
                Button("Import Interfaces CSV") { chooseFile(.interface) }
                Button("Import Routes CSV") { chooseFile(.route) }
            }
            Text("Find a subnet containing an IPv4 address or subnet. Review the imported evidence before using the result.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("IP address or subnet, e.g. 10.1.2.3 or 10.1.2.0/24", text: $address)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") { address = "" }.disabled(address.isEmpty)
            }
            HStack {
                Text("Interfaces: \(records.filter { $0.kind == .interface }.count) · Routes: \(records.filter { $0.kind == .route }.count)")
                Spacer()
                Button("Done") { dismiss() }
            }.font(.callout)
            if (try? store.networkRecords()) == nil { Text("Unable to read the existing network inventory. No data was changed.").foregroundStyle(.red) }
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Enter an IP address", systemImage: "magnifyingglass", description: Text("Import CSV files, then enter an IPv4 address or subnet to see matching records."))
            } else if let results {
                if results.isEmpty {
                    ContentUnavailableView("No matching records", systemImage: "network.slash", description: Text("Check the input and imported data. No match does not mean a subnet or path does not exist."))
                } else {
                    List(results) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(store.firewalls.first(where: { $0.id == record.firewallID })?.name ?? record.firewall).font(.headline)
                                Text(record.kind == .interface ? "Interface match" : "Route match").font(.caption).padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                Spacer()
                                Text("\(record.subnet)").monospaced()
                            }
                            Text(details(record)).font(.callout)
                            Text("Source: \(record.source), CSV record \(record.row) · Imported \(record.importedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            } else {
                ContentUnavailableView("Invalid IPv4 address or subnet", systemImage: "exclamationmark.triangle", description: Text("Enter an IPv4 address or CIDR subnet such as 10.1.2.0/24."))
            }
            Text("Route matches are the most specific imported entries per firewall and routing context, not a verified forwarding path. Route status, metrics, NAT, PBF, dynamic changes and other devices are not evaluated. An address without a prefix is treated as /32.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(minWidth: 720, minHeight: 520)
        .sheet(item: $importRequest) { request in NetworkImportView(store: store, request: request) }
        .alert("Unable to Import CSV", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func details(_ record: NetworkRecord) -> String {
        [("Management IP", store.firewalls.first(where: { $0.id == record.firewallID })?.managementIP ?? record.managementIP ?? ""), ("Interface", record.interface), ("Zone", record.zone), ("Router / VSYS", record.router), ("Next hop", record.nextHop)]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: " · ")
    }
    private func chooseFile(_ kind: NetworkRecordKind) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 20 * 1024 * 1024 else { throw CSVReadError.size }
            guard let text = String(data: data, encoding: .utf8) else { throw NSError(domain: "CSV", code: 1, userInfo: [NSLocalizedDescriptionKey: "Save the CSV as UTF-8 and try again."]) }
            importRequest = ImportRequest(kind: kind, source: url.lastPathComponent, table: try CSVTable(text: text))
        } catch { self.error = error.localizedDescription }
    }
}
private struct ImportRequest: Identifiable {
    let id = UUID()
    let kind: NetworkRecordKind
    let source: String
    let table: CSVTable
}
private struct NetworkImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TicketStore
    let request: ImportRequest
    @State private var map: NetworkColumnMap
    @State private var firewallName = ""
    @State private var firewallID = ""
    @State private var managementIP = ""
    @State private var deviceGroup = ""
    @State private var excludedZones: Set<String> = []
    @State private var confirmReplace = false
    @State private var error: String?
    init(store: TicketStore, request: ImportRequest) {
        self.store = store; self.request = request
        _map = State(initialValue: .suggest(request.table.headers, kind: request.kind))
    }
    private var report: NetworkImportReport { map.records(from: request.table, kind: request.kind, source: request.source, firewallName: chosenName, managementIP: managementIP) }
    private var selectedFirewall: FirewallDefinition? { store.firewalls.first { $0.id == firewallID } }
    private var chosenName: String { selectedFirewall?.name ?? firewallName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var zones: [String] { request.kind == .interface ? map.zoneNames(in: request.table) : [] }
    private var validManagementIP: Bool {
        let value = managementIP.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || (!value.contains("/") && IPv4Network(value) != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import \(request.kind.title) CSV").font(.title2.bold())
            Text("\(request.source) · \(request.table.rows.count) records").foregroundStyle(.secondary)
            Text("Choose the firewall for this file and review the columns and zones before importing.")
            HStack {
                Text("Firewall")
                Picker("Firewall", selection: $firewallID) {
                    Text("Add New Firewall").tag("")
                    ForEach(store.firewalls) { firewall in Text(firewall.name).tag(firewall.id) }
                }.labelsHidden()
            }
            if firewallID.isEmpty {
                HStack { Text("Firewall name"); TextField("Enter firewall name", text: $firewallName).textFieldStyle(.roundedBorder) }
                HStack { Text("Device Group"); TextField("Optional device group", text: $deviceGroup).textFieldStyle(.roundedBorder) }
            }
            HStack { Text("Management IP"); TextField("Optional IPv4 address for this file", text: $managementIP).textFieldStyle(.roundedBorder) }
            if !validManagementIP { Text("Enter a valid IPv4 management address without a prefix.").font(.caption).foregroundStyle(.red) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text(request.kind == .interface ? "Address / Subnet *" : "Destination / Subnet *"); column($map.subnet) }
                GridRow { Text("Interface"); column($map.interface) }
                GridRow { Text("Zone"); column($map.zone) }
                GridRow { Text("Virtual Router / VSYS"); column($map.router) }
                if request.kind == .route { GridRow { Text("Next Hop"); column($map.nextHop) } }
            }
            Text("\(report.records.count) records ready · \(report.skippedRows.count) records skipped").fontWeight(.semibold)
            if !report.skippedRows.isEmpty {
                Text("Skipped CSV records: \(report.skippedRows.prefix(15).map(String.init).joined(separator: ", "))\(report.skippedRows.count > 15 ? " …" : ""). Check firewall names and IPv4 CIDR values.").font(.caption).foregroundStyle(.secondary)
            }
            List(report.records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.subnet) · record \(record.row)")
                    Text([record.interface, record.zone, record.router, record.nextHop].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(minHeight: 100, maxHeight: 150)
            if !zones.isEmpty {
                Text("Zones found — select those to add").fontWeight(.semibold)
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(zones, id: \.self) { zone in
                            Toggle(zone, isOn: Binding(get: { !excludedZones.contains(zone) }, set: { if $0 { excludedZones.remove(zone) } else { excludedZones.insert(zone) } }))
                        }
                    }
                }.frame(maxHeight: 110)
                Text("Verify zone names before importing; existing zones are kept.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Import replaces \(request.kind.title.lowercased()) records for the selected firewall. Other firewalls and existing zones are kept.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Import") { confirmReplace = true }.buttonStyle(.borderedProminent).disabled(chosenName.isEmpty || !validManagementIP || map.subnet < 0 || report.records.isEmpty) }
        }
        .padding(20).frame(width: 660, height: 760)
        .onChange(of: firewallID) { _, id in
            let selected = store.firewalls.first { $0.id == id }
            managementIP = selected?.managementIP ?? ""
            deviceGroup = selected?.deviceGroup ?? ""
        }
        .confirmationDialog("Replace imported \(request.kind.title.lowercased()) records?", isPresented: $confirmReplace) {
            Button("Replace and Import") {
                do {
                    let name = chosenName
                    var firewall = selectedFirewall ?? FirewallDefinition(id: UUID().uuidString, name: name, deviceGroup: deviceGroup, zones: [], isActive: true)
                    let address = managementIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    firewall.managementIP = address.isEmpty ? nil : address
                    let records = map.records(from: request.table, kind: request.kind, source: request.source, firewallName: name, managementIP: address).records
                    try store.importNetworkRecords(records, kind: request.kind, firewall: firewall, isNew: selectedFirewall == nil, zones: zones.filter { !excludedZones.contains($0) })
                    dismiss()
                }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Existing \(request.kind.title.lowercased()) records for \(chosenName) will be replaced by \(report.records.count) records. Other firewalls are kept.") }
        .alert("Unable to Import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func column(_ selection: Binding<Int>) -> some View {
        Picker("Column", selection: selection) {
            Text("Not selected").tag(-1)
            ForEach(request.table.headers.indices, id: \.self) { index in Text("\(request.table.headers[index]) (\(index + 1))").tag(index) }
        }.labelsHidden().frame(maxWidth: .infinity)
    }
}
