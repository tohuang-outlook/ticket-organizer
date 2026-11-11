import Foundation
import Combine

struct IPv4Network: Equatable {
    let address: UInt32
    let prefix: Int
    var mask: UInt32 { prefix == 0 ? 0 : UInt32.max << (32 - prefix) }
    var network: UInt32 { address & mask }

    init?(_ input: String) {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts.isEmpty else { return nil }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard !octet.isEmpty, octet.allSatisfy({ $0.isASCII && $0.isNumber }), let n = UInt8(octet) else { return nil }
            value = (value << 8) | UInt32(n)
        }
        let length: Int
        if parts.count == 2 {
            guard let n = Int(parts[1]), (0...32).contains(n) else { return nil }
            length = n
        } else { length = 32 }
        address = value
        prefix = length
    }
    func contains(_ other: IPv4Network) -> Bool { prefix <= other.prefix && (other.address & mask) == network }
    var cidr: String { "\((network >> 24) & 255).\((network >> 16) & 255).\((network >> 8) & 255).\(network & 255)/\(prefix)" }
}

enum CSVReadError: LocalizedError {
    case malformed, empty, size
    var errorDescription: String? {
        switch self {
        case .malformed: "The CSV contains an incomplete or invalid quoted field."
        case .empty: "The CSV must contain a header and at least one data row."
        case .size: "The CSV is too large (maximum 20 MB)."
        }
    }
}

struct CSVTable {
    let headers: [String]
    let rows: [[String]]
    init(text: String) throws {
        var records: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false, atStart = true
        let chars = Array(text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text)
        var i = 0
        func endField() { row.append(field); field = ""; atStart = true; closedQuote = false }
        func endRow() { endField(); if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { records.append(row) }; row = [] }
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closedQuote = true }
                } else { field.append(c) }
            } else if c == "," { endField() }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                endRow()
                if c == "\r" && i + 1 < chars.count && chars[i+1] == "\n" { i += 1 }
            } else if c == "\"" {
                guard atStart && !closedQuote else { throw CSVReadError.malformed }
                quoted = true; atStart = false
            } else {
                guard !closedQuote else { throw CSVReadError.malformed }
                field.append(c); atStart = false
            }
            i += 1
        }
        guard !quoted else { throw CSVReadError.malformed }
        if !row.isEmpty || !field.isEmpty || closedQuote { endRow() }
        guard records.count >= 2 else { throw CSVReadError.empty }
        headers = records[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        rows = Array(records.dropFirst())
    }
}

enum NetworkRecordKind: String, Codable, CaseIterable, Identifiable {
    case interface, route
    var id: String { rawValue }
    var title: String { self == .interface ? "Interface" : "Route" }
}
struct NetworkRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: NetworkRecordKind
    var firewall: String
    var firewallID: String? = nil
    var managementIP: String? = nil
    var subnet: String
    var interface: String
    var zone: String
    var router: String
    var nextHop: String
    var source: String
    var row: Int
    var importedAt: Date
}
struct NetworkImportReport {
    var records: [NetworkRecord]
    var skippedRows: [Int]
}
struct NetworkColumnMap {
    var firewall: Int = -1, subnet: Int = -1, interface: Int = -1, zone: Int = -1, router: Int = -1, nextHop: Int = -1
    func zoneNames(in table: CSVTable) -> [String] {
        guard zone >= 0 else { return [] }
        var seen = Set<String>()
        return table.rows.compactMap { row in
            guard zone < row.count else { return nil }
            let value = row[zone].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != "-", value.caseInsensitiveCompare("N/A") != .orderedSame, seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func suggest(_ headers: [String], kind: NetworkRecordKind) -> NetworkColumnMap {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        func find(_ names: [String]) -> Int { names.compactMap { name in headers.firstIndex { norm($0) == norm(name) } }.first ?? -1 }
        return NetworkColumnMap(firewall: find(["firewall", "firewall name", "hostname", "device", "device name"]), subnet: find(kind == .interface ? ["subnet", "network", "ip addresses", "ip address", "address", "ip"] : ["destination", "destination subnet", "subnet", "network", "prefix"]), interface: find(kind == .interface ? ["interface", "interface name", "name"] : ["interface", "interface name", "egress interface"]), zone: find(["zone", "security zone"]), router: find(["virtual router", "virtual-router", "vr", "vsys", "routing instance"]), nextHop: find(["next hop", "nexthop", "gateway"]))
    }
    func records(from table: CSVTable, kind: NetworkRecordKind, source: String, firewallName: String = "", managementIP: String = "", now: Date = Date()) -> NetworkImportReport {
        var output: [NetworkRecord] = [], skipped: [Int] = []
        func value(_ row: [String], _ index: Int) -> String { index >= 0 && index < row.count ? row[index].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
        for (index, row) in table.rows.enumerated() {
            let manualName = firewallName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rowName = manualName.isEmpty ? value(row, firewall) : manualName
            let subnetText = value(row, subnet)
            guard !rowName.isEmpty, IPv4Network(subnetText) != nil else { skipped.append(index + 2); continue }
            let management = managementIP.trimmingCharacters(in: .whitespacesAndNewlines)
            output.append(NetworkRecord(kind: kind, firewall: rowName, managementIP: management.isEmpty ? nil : management, subnet: subnetText, interface: value(row, interface), zone: value(row, zone), router: value(row, router), nextHop: value(row, nextHop), source: source, row: index + 2, importedAt: now))
        }
        return NetworkImportReport(records: output, skippedRows: skipped)
    }
}
struct NetworkLookup {
    struct Candidate: Identifiable {
        let id: String
        let name: String
        let sourceMatches: [NetworkRecord]
        let destinationMatches: [NetworkRecord]
    }

    static func possibleFirewalls(source: [NetworkRecord], destination: [NetworkRecord], firewalls: [FirewallDefinition]) -> [Candidate] {
        func identity(_ record: NetworkRecord) -> (String, String) {
            if let id = record.firewallID {
                return ("id:" + id, firewalls.first(where: { $0.id == id })?.name ?? record.firewall)
            }
            let matches = firewalls.filter { $0.name.caseInsensitiveCompare(record.firewall) == .orderedSame || $0.id.caseInsensitiveCompare(record.firewall) == .orderedSame }
            if matches.count == 1 { return ("id:" + matches[0].id, matches[0].name) }
            return ("name:" + record.firewall.lowercased(), record.firewall)
        }
        let sources = Dictionary(grouping: source, by: { identity($0).0 })
        let destinations = Dictionary(grouping: destination, by: { identity($0).0 })
        return sources.keys.compactMap { key in
            guard let left = sources[key], let first = left.first, let right = destinations[key], !right.isEmpty else { return nil }
            return Candidate(id: key, name: identity(first).1, sourceMatches: left, destinationMatches: right)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func matches(_ input: String, records: [NetworkRecord]) -> [NetworkRecord]? {
        guard let target = IPv4Network(input) else { return nil }
        let matches = records.filter { IPv4Network($0.subnet)?.contains(target) == true }
        // Retain every interface match, and the longest route matches per firewall and routing context.
        let routes = matches.filter { $0.kind == .route }
        let best = Dictionary(grouping: routes, by: { ($0.firewallID ?? $0.firewall.lowercased()) + "\u{0}" + $0.router.lowercased() }).values.flatMap { group -> [NetworkRecord] in
            let maxPrefix = group.compactMap { IPv4Network($0.subnet)?.prefix }.max() ?? -1
            return group.filter { IPv4Network($0.subnet)?.prefix == maxPrefix }
        }
        return (matches.filter { $0.kind == .interface } + best).sorted {
            if $0.kind != $1.kind { return $0.kind == .interface }
            let left = IPv4Network($0.subnet)?.prefix ?? 0, right = IPv4Network($1.subnet)?.prefix ?? 0
            return left == right ? $0.firewall.localizedStandardCompare($1.firewall) == .orderedAscending : left > right
        }
    }
}
@MainActor final class NetworkInventory: ObservableObject {
    static let shared = NetworkInventory()
    @Published private(set) var records: [NetworkRecord] = []
    @Published var error: String?
    private let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TicketOrganizer/network-inventory.json")
        do { if FileManager.default.fileExists(atPath: self.url.path) { records = try JSONDecoder().decode([NetworkRecord].self, from: Data(contentsOf: self.url)) } }
        catch { self.error = "Network inventory could not be opened. It has not been overwritten: \(error.localizedDescription)" }
    }
    func replace(kind: NetworkRecordKind, with imported: [NetworkRecord]) throws {
        guard error == nil else { throw NSError(domain: "NetworkInventory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network inventory could not be opened; import is disabled to protect the existing file."]) }
        let importedNames = Set(imported.map { $0.firewall.lowercased() })
        let next = records.filter { $0.kind != kind || !importedNames.contains($0.firewall.lowercased()) } + imported
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        records = next
    }
}
