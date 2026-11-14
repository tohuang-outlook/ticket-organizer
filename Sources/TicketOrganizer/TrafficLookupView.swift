import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TrafficLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TicketStore
    @State private var sourceAddress = ""
    @State private var destinationAddress = ""
    @State private var importRequest: ImportRequest?
    @State private var error: String?

    private var records: [NetworkRecord] { (try? store.networkRecords()) ?? [] }
    var body: some View {
        let allRecords = records
        let sourceResults = NetworkLookup.matches(sourceAddress, records: allRecords)
        let destinationResults = NetworkLookup.matches(destinationAddress, records: allRecords)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Traffic Lookup").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Import Interfaces CSV / TXT") { chooseFile(.interface) }
                Button("Import Routes CSV") { chooseFile(.route) }
            }
            Text("Compare the imported subnet matches for a source and destination. Review the evidence before using the results.")
                .foregroundStyle(.secondary)
            HStack {
                Text("Interfaces: \(allRecords.filter { $0.kind == .interface }.count) · Routes: \(allRecords.filter { $0.kind == .route }.count)")
                Spacer()
                Button("Done") { dismiss() }
            }.font(.system(size: 16))
            if (try? store.networkRecords()) == nil { Text("Unable to read the existing network inventory. No data was changed.").foregroundStyle(.red) }
            PossibleTrafficPathView(source: sourceResults, destination: destinationResults, firewalls: store.firewalls)
            HStack(alignment: .top, spacing: 16) {
                TrafficLookupColumn(title: "Source IP", address: $sourceAddress, results: sourceResults, firewalls: store.firewalls)
                Divider()
                TrafficLookupColumn(title: "Destination IP", address: $destinationAddress, results: destinationResults, firewalls: store.firewalls)
            }
            Text("Source and destination are matched independently; this is not a verified path. Route status, metrics, NAT, PBF, dynamic changes and other devices are not evaluated. An address without a prefix is treated as /32.")
                .font(.system(size: 16)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 16))
        .padding(20).frame(minWidth: 720, minHeight: 520)
        .sheet(item: $importRequest) { request in NetworkImportView(store: store, request: request) }
        .alert("Unable to Import File", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
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
            let table = try kind == .interface && url.pathExtension.lowercased() == "txt" ? InterfaceTextParser.parse(text) : CSVTable(text: text)
            importRequest = ImportRequest(kind: kind, source: url.lastPathComponent, table: table)
        } catch { self.error = error.localizedDescription }
    }
}
private struct PossibleTrafficPathView: View {
    let source: [NetworkRecord]?
    let destination: [NetworkRecord]?
    let firewalls: [FirewallDefinition]
    @State private var expanded = true
    private var candidates: [NetworkLookup.Candidate] {
        guard let source, let destination else { return [] }
        return NetworkLookup.possibleFirewalls(source: source, destination: destination, firewalls: firewalls)
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Candidates appear in both lookup results. Source matches can include return routes; they do not establish ingress, path order, connectivity or policy approval. Different routing contexts may be unrelated.")
                    .font(.system(size: 16)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if source == nil || destination == nil {
                    Text("Enter a valid source and destination to see common devices.").foregroundStyle(.secondary)
                } else if candidates.isEmpty {
                    Text("No common devices found in the imported matches. This does not establish that a path is absent.").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(candidates) { candidate in
                                DisclosureGroup("\(candidate.name)\(firewalls.first(where: { "id:" + $0.id == candidate.id }).map { " · \($0.effectiveDeviceType.title)" } ?? "") — \(candidate.sourceMatches.count) source / \(candidate.destinationMatches.count) destination matches") {
                                    HStack(alignment: .top, spacing: 16) {
                                        evidence("Source-side matches", candidate.sourceMatches)
                                        evidence("Destination-side matches", candidate.destinationMatches)
                                    }
                                }
                            }
                        }
                    }.frame(maxHeight: 190)
                }
            }.padding(.top, 6)
        } label: { Text("Possible Traffic Path — common device candidates").font(.system(size: 16, weight: .semibold)) }
    }
    private func evidence(_ title: String, _ records: [NetworkRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.semibold)
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.kind == .interface ? "Interface" : "Route"): \(record.subnet)").fontWeight(.medium)
                    Text([record.zone.isEmpty ? "Zone: unknown" : "Zone\(record.zoneMayBeTruncated == true ? " (may be truncated)" : ""): \(record.zone)", record.interface.isEmpty ? "Interface: unknown" : "Interface: \(record.interface)", record.router.isEmpty ? "Routing context: unknown" : "Routing context: \(record.router)", record.nextHop.isEmpty ? "" : "Next hop: \(record.nextHop)", record.interfaceStatus ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    Text("\(record.source), \(record.sourceLine == nil ? "CSV record" : "TXT line") \(record.row) · \(record.importedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 16)).foregroundStyle(.secondary)
                }.font(.system(size: 16)).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct TrafficLookupColumn: View {
    let title: String
    @Binding var address: String
    let results: [NetworkRecord]?
    let firewalls: [FirewallDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold))
            HStack {
                TextField("IPv4 address or CIDR subnet", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(title)
                Button("Clear") { address = "" }.disabled(address.isEmpty)
                    .accessibilityLabel("Clear \(title)")
            }
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Enter \(title)", systemImage: "magnifyingglass", description: Text("Enter an IPv4 address or subnet."))
            } else if let results {
                if results.isEmpty {
                    ContentUnavailableView("No matching records", systemImage: "network.slash", description: Text("Check the input and imported data."))
                } else {
                    let interfaces = results.filter { $0.kind == .interface }
                    let routes = results.filter { $0.kind == .route }
                    List {
                        Section {
                            if interfaces.isEmpty {
                                Text("No imported interface subnet contains this address.").foregroundStyle(.secondary)
                            } else {
                                ForEach(interfaces) { record in resultRow(record) }
                            }
                        } header: {
                            Text("Interface subnet matches (\(interfaces.count))").font(.system(size: 16, weight: .semibold))
                        }
                        if !routes.isEmpty {
                            Section {
                                ForEach(routes) { record in resultRow(record) }
                            } header: {
                                Text("Route matches (\(routes.count))").font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Invalid IPv4 address or subnet", systemImage: "exclamationmark.triangle", description: Text("Use an IPv4 address or CIDR subnet."))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func resultRow(_ record: NetworkRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(firewalls.first(where: { $0.id == record.firewallID })?.name ?? record.firewall).font(.system(size: 16, weight: .semibold))
                if let device = firewalls.first(where: { $0.id == record.firewallID }) { Text(device.effectiveDeviceType.title).font(.system(size: 16)).foregroundStyle(.secondary) }
                Text(record.kind == .interface ? "Interface match" : "Route match").font(.system(size: 16)).padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            Text(record.subnet).monospaced()
            Text(details(record)).font(.system(size: 16))
            Text("Source: \(record.source), \(record.sourceLine == nil ? "CSV record" : "TXT line") \(record.row) · Imported \(record.importedAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 16)).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
    private func details(_ record: NetworkRecord) -> String {
        [("Management IP", firewalls.first(where: { $0.id == record.firewallID })?.managementIP ?? record.managementIP ?? ""), ("Interface", record.interface), (record.zoneMayBeTruncated == true ? "Zone (may be truncated)" : "Zone", record.zone), ("Router / VSYS", record.router), ("Next hop", record.nextHop), ("Interface status", record.interfaceStatus ?? "")]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: " · ")
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
    @State private var deviceType: NetworkDeviceType = .firewall
    @State private var managementIP = ""
    @State private var deviceGroup = ""
    @State private var excludedZones: Set<String> = []
    @State private var selectedTextZones: Set<String> = []
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
            Text("Import \(request.kind.title) \(request.table.textFormat == nil ? "CSV" : "TXT")").font(.title2.bold())
            Text("\(request.source) · \(request.table.rows.count) records").foregroundStyle(.secondary)
            if let format = request.table.textFormat {
                Text(format == "PAN-OS" ? "PAN-OS table zone names can be truncated. Verify names before adding zones; none are selected by default." : "Cisco configuration: only IPv4 interface addresses with subnet masks are imported. Operational state and routing paths are not verified.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Choose the device for this file and review the columns and zones before importing.")
            HStack {
                Text("Device")
                Picker("Device", selection: $firewallID) {
                    Text("Add New Device").tag("")
                    ForEach(store.firewalls.sorted { left, right in
                        let order = left.name.localizedStandardCompare(right.name)
                        return order == .orderedSame ? left.id < right.id : order == .orderedAscending
                    }) { firewall in Text("\(firewall.name) · \(firewall.effectiveDeviceType.title)").tag(firewall.id) }
                }.labelsHidden()
            }
            if firewallID.isEmpty {
                HStack { Text("Device type"); Picker("Device type", selection: $deviceType) { ForEach(NetworkDeviceType.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                HStack { Text("Device name"); TextField("Enter device name", text: $firewallName).textFieldStyle(.roundedBorder) }
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
                Text("Skipped \(request.table.sourceLines == nil ? "CSV records" : "TXT lines"): \(report.skippedRows.prefix(15).map(String.init).joined(separator: ", "))\(report.skippedRows.count > 15 ? " …" : ""). Check device names and IPv4 CIDR values.").font(.caption).foregroundStyle(.secondary)
            }
            List(report.records) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(record.subnet) · \(record.sourceLine == nil ? "record" : "line") \(record.row)")
                    Text([record.interface, record.zone, record.router, record.nextHop, record.interfaceStatus ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(minHeight: 100, maxHeight: 150)
            if !zones.isEmpty {
                Text("Zones found — select those to add").fontWeight(.semibold)
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(zones, id: \.self) { zone in
                            Toggle(zone, isOn: Binding(get: { request.table.textFormat == "PAN-OS" ? selectedTextZones.contains(zone) : !excludedZones.contains(zone) }, set: { value in
                                if request.table.textFormat == "PAN-OS" { if value { selectedTextZones.insert(zone) } else { selectedTextZones.remove(zone) } }
                                else { if value { excludedZones.remove(zone) } else { excludedZones.insert(zone) } }
                            }))
                        }
                    }
                }.frame(maxHeight: 110)
                Text("Verify zone names before importing; existing zones are kept.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Import replaces \(request.kind.title.lowercased()) records for the selected device. Other devices and existing zones are kept.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Import") { confirmReplace = true }.buttonStyle(.borderedProminent).disabled(chosenName.isEmpty || !validManagementIP || map.subnet < 0 || report.records.isEmpty) }
        }
        .padding(20).frame(width: 660, height: 760)
        .onChange(of: firewallID) { _, id in
            let selected = store.firewalls.first { $0.id == id }
            managementIP = selected?.managementIP ?? ""
            deviceGroup = selected?.deviceGroup ?? ""
            deviceType = selected?.effectiveDeviceType ?? .firewall
        }
        .confirmationDialog("Replace imported \(request.kind.title.lowercased()) records?", isPresented: $confirmReplace) {
            Button("Replace and Import") {
                do {
                    let name = chosenName
                    var firewall = selectedFirewall ?? FirewallDefinition(id: UUID().uuidString, name: name, deviceGroup: deviceGroup, zones: [], isActive: true, deviceType: deviceType)
                    let address = managementIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    firewall.managementIP = address.isEmpty ? nil : address
                    let records = map.records(from: request.table, kind: request.kind, source: request.source, firewallName: name, managementIP: address).records
                    try store.importNetworkRecords(records, kind: request.kind, firewall: firewall, isNew: selectedFirewall == nil, zones: zones.filter { request.table.textFormat == "PAN-OS" ? selectedTextZones.contains($0) : !excludedZones.contains($0) })
                    dismiss()
                }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Existing \(request.kind.title.lowercased()) records for \(chosenName) will be replaced by \(report.records.count) records. Other devices are kept.") }
        .alert("Unable to Import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func column(_ selection: Binding<Int>) -> some View {
        Picker("Column", selection: selection) {
            Text("Not selected").tag(-1)
            ForEach(request.table.headers.indices, id: \.self) { index in Text("\(request.table.headers[index]) (\(index + 1))").tag(index) }
        }.labelsHidden().frame(maxWidth: .infinity)
    }
}
