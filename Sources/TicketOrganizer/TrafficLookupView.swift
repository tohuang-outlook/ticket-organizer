import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TrafficLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inventory = NetworkInventory.shared
    @State private var address = ""
    @State private var importRequest: ImportRequest?
    @State private var error: String?

    private var results: [NetworkRecord]? { NetworkLookup.matches(address, records: inventory.records) }
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
                Text("Interfaces: \(inventory.records.filter { $0.kind == .interface }.count) · Routes: \(inventory.records.filter { $0.kind == .route }.count)")
                Spacer()
                Button("Done") { dismiss() }
            }.font(.callout)
            if let error = inventory.error { Text(error).foregroundStyle(.red) }
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Enter an IP address", systemImage: "magnifyingglass", description: Text("Import CSV files, then enter an IPv4 address or subnet to see matching records."))
            } else if let results {
                if results.isEmpty {
                    ContentUnavailableView("No matching records", systemImage: "network.slash", description: Text("Check the input and imported data. No match does not mean a subnet or path does not exist."))
                } else {
                    List(results) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.firewall).font(.headline)
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
        .sheet(item: $importRequest) { request in NetworkImportView(inventory: inventory, request: request) }
        .alert("Unable to Import CSV", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func details(_ record: NetworkRecord) -> String {
        [("Interface", record.interface), ("Zone", record.zone), ("Router / VSYS", record.router), ("Next hop", record.nextHop)]
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
    @ObservedObject var inventory: NetworkInventory
    let request: ImportRequest
    @State private var map: NetworkColumnMap
    @State private var confirmReplace = false
    @State private var error: String?
    init(inventory: NetworkInventory, request: ImportRequest) {
        self.inventory = inventory; self.request = request
        _map = State(initialValue: .suggest(request.table.headers, kind: request.kind))
    }
    private var report: NetworkImportReport { map.records(from: request.table, kind: request.kind, source: request.source) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import \(request.kind.title) CSV").font(.title2.bold())
            Text("\(request.source) · \(request.table.rows.count) records").foregroundStyle(.secondary)
            Text("Select the columns that contain each field. The firewall and IPv4 CIDR columns are required.")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("Firewall *"); column($map.firewall) }
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
            List(report.records.prefix(5)) { record in
                Text("\(record.firewall) · \(record.subnet) · record \(record.row)")
            }.frame(minHeight: 100, maxHeight: 150)
            Text("Import replaces the previously imported \(request.kind.title.lowercased()) records on this Mac. Ticket notes and firewall settings are unaffected.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Import") { confirmReplace = true }.buttonStyle(.borderedProminent).disabled(map.firewall < 0 || map.subnet < 0 || report.records.isEmpty || inventory.error != nil) }
        }
        .padding(20).frame(width: 660, height: 570)
        .confirmationDialog("Replace imported \(request.kind.title.lowercased()) records?", isPresented: $confirmReplace) {
            Button("Replace and Import") {
                do { try inventory.replace(kind: request.kind, with: report.records); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The previous \(request.kind.title.lowercased()) import will be replaced by \(report.records.count) records.") }
        .alert("Unable to Import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func column(_ selection: Binding<Int>) -> some View {
        Picker("Column", selection: selection) {
            Text("Not selected").tag(-1)
            ForEach(request.table.headers.indices, id: \.self) { index in Text("\(request.table.headers[index]) (\(index + 1))").tag(index) }
        }.labelsHidden().frame(maxWidth: .infinity)
    }
}
