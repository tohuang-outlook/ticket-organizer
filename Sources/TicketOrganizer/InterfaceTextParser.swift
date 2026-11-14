import Foundation

enum InterfaceTextParser {
    static func parse(_ text: String) throws -> CSVTable {
        let lines = text.components(separatedBy: .newlines)
        if lines.contains(where: { $0.localizedCaseInsensitiveContains("total configured logical interfaces") }) {
            return try parsePAN(lines)
        }
        if lines.contains(where: { stripTimestamp($0).hasPrefix("interface ") }) {
            return try parseCisco(lines)
        }
        // A text file may also contain ordinary comma-separated data.
        if lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.contains(",") == true {
            return try CSVTable(text: text)
        }
        throw NSError(domain: "InterfaceText", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported interface text. Use a Cisco running configuration, PAN-OS show interface all, or a CSV file."])
    }

    private static func stripTimestamp(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "^[0-9]+(?:\\.[0-9]+)?: ?", with: "", options: .regularExpression)
    }

    private static func parseCisco(_ lines: [String]) throws -> CSVTable {
        var rows: [[String]] = [], numbers: [Int] = []
        var name = "", vrf = "", shutdown = false
        var addresses: [(String, Int)] = []
        func flush() {
            for (address, line) in addresses {
                rows.append([name, address, "", vrf, shutdown ? "Administratively down" : "Not verified"])
                numbers.append(line)
            }
            addresses = []; vrf = ""; shutdown = false
        }
        for (index, original) in lines.enumerated() {
            let line = stripTimestamp(original).replacingOccurrences(of: "\u{feff}", with: "")
            if line.hasPrefix("interface ") {
                flush(); name = String(line.dropFirst("interface ".count)).trimmingCharacters(in: .whitespaces)
            } else if !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                flush(); name = ""
            } else if !name.isEmpty {
                let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if words.count >= 3 && words[0] == "vrf" && words[1] == "forwarding" { vrf = words[2] }
                if words.count >= 4 && words[0] == "ip" && words[1] == "vrf" && words[2] == "forwarding" { vrf = words[3] }
                if words == ["shutdown"] { shutdown = true }
                if words == ["no", "shutdown"] { shutdown = false }
                if words.count >= 4 && words[0] == "ip" && words[1] == "address", let prefix = maskPrefix(words[3]), IPv4Network(words[2]) != nil {
                    addresses.append(("\(words[2])/\(prefix)", index + 1))
                }
            }
        }
        flush()
        guard !rows.isEmpty else { throw noAddresses() }
        return CSVTable(headers: ["Interface", "Address", "Zone", "Virtual Router", "Administrative status"], rows: rows, sourceLines: numbers, textFormat: "Cisco configuration")
    }

    private static func maskPrefix(_ text: String) -> Int? {
        guard let mask = IPv4Network(text), !text.contains("/") else { return nil }
        let n = mask.address, prefix = n.nonzeroBitCount
        let expected: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        return n == expected ? prefix : nil
    }

    private static func parsePAN(_ lines: [String]) throws -> CSVTable {
        guard let start = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("total configured logical interfaces") }),
              let headerIndex = lines.indices.dropFirst(start + 1).first(where: { lines[$0].lowercased().contains("vsys zone") && lines[$0].lowercased().contains("forwarding") }) else { throw noAddresses() }
        let header = lines[headerIndex].lowercased()
        func offset(_ word: String) -> Int? { header.range(of: word).map { header.distance(from: header.startIndex, to: $0.lowerBound) } }
        guard let zoneStart = offset("zone"), let forwardStart = offset("forwarding"), let tagStart = offset("tag"), let addressStart = offset("address") else { throw noAddresses() }
        func slice(_ line: String, _ start: Int, _ end: Int) -> String {
            let chars = Array(line); guard start < chars.count else { return "" }
            return String(chars[start..<min(end, chars.count)]).trimmingCharacters(in: .whitespaces)
        }
        var rows: [[String]] = [], numbers: [Int] = []
        for i in (headerIndex + 1)..<lines.count {
            let line = lines[i], prefix = slice(line, 0, zoneStart).split(whereSeparator: { $0.isWhitespace })
            guard prefix.count >= 3, Int(prefix[1]) != nil, Int(prefix[2]) != nil else { continue }
            let address = slice(line, addressStart, line.count).split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            guard IPv4Network(address) != nil, address.contains("/") else { continue }
            let zone = slice(line, zoneStart, forwardStart)
            let forwarding = slice(line, forwardStart, tagStart)
            let router = forwarding.hasPrefix("vr:") ? String(forwarding.dropFirst(3)) : ""
            rows.append([String(prefix[0]), address, zone, router, "Not verified"]); numbers.append(i + 1)
        }
        guard !rows.isEmpty else { throw noAddresses() }
        return CSVTable(headers: ["Interface", "Address", "Zone", "Virtual Router", "Administrative status"], rows: rows, sourceLines: numbers, textFormat: "PAN-OS")
    }
    private static func noAddresses() -> NSError {
        NSError(domain: "InterfaceText", code: 2, userInfo: [NSLocalizedDescriptionKey: "No supported IPv4 interface addresses with valid subnet masks were found in this file."])
    }
}
