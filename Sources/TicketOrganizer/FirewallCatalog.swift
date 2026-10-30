import Foundation

struct FirewallDefinition: Codable, Identifiable, Equatable {
    // Stable identifiers keep existing tickets connected when a firewall is renamed.
    var id: String
    var name: String
    var deviceGroup: String
    var zones: [String]
    var isActive: Bool

    static var placeholders: [FirewallDefinition] {
        (1...5).map { number in
            let name = String(format: "FW%02d", number)
            return FirewallDefinition(id: name, name: name, deviceGroup: "device group \(number)", zones: (1...4).map { "zone \($0)" }, isActive: true)
        }
    }
}

struct FirewallCLIResult {
    var hostname: String?
    var zones: [String]
    var hasMultipleHostnames: Bool
    var zonesMayBeTruncated: Bool
}

enum FirewallCLIParser {
    // Supports PAN-OS system info, set-format config, and show interface all output.
    // Only explicit fields are read; the pasted CLI text is never executed or saved.
    static func parse(_ text: String) -> FirewallCLIResult {
        func capture(_ pattern: String, groups: [Int]) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else { return [] }
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                for group in groups {
                    if let range = Range(match.range(at: group), in: text) {
                        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty && !value.hasPrefix("<") { return value }
                    }
                }
                return nil
            }
        }
        func unique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.filter { seen.insert($0.lowercased()).inserted }
        }
        let names = unique(capture(#"^[\t ]*hostname[\t ]*:[\t ]*([^\s]+)[\t ]*\r?$"#, groups: [1]) +
                           capture(#"^[\t ]*set[\t ]+deviceconfig[\t ]+system[\t ]+hostname[\t ]+(?:"([^"]+)"|(\S+))[\t ]*\r?$"#, groups: [1, 2]) +
                           capture(#"^[\t ]*[^\s@]+@([A-Za-z0-9._-]+)(?:\((?:active|passive)\))?[>#][\t ]*show[\t ]+interface[\t ]+all[\t ]*\r?$"#, groups: [1]))
        let setZones = unique(capture(#"^[\t ]*set[\t ]+zone[\t ]+(?:"([^"]+)"|(\S+))(?:[\t ]|\r?$)"#, groups: [1, 2]))

        // Read the fixed-width logical-interface table by its headers. Empty zone
        // fields must not be confused with the adjacent forwarding field.
        var inLogicalSection = false
        var bounds: (Int, Int)?
        var tableZones: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.lowercased().contains("total configured logical interfaces:") {
                inLogicalSection = true
                bounds = nil
                continue
            }
            guard inLogicalSection else { continue }
            if bounds == nil {
                if let zone = line.range(of: "zone", options: .caseInsensitive),
                   let forwarding = line.range(of: "forwarding", options: .caseInsensitive),
                   line.lowercased().contains("vsys"), zone.lowerBound < forwarding.lowerBound {
                    bounds = (line.distance(from: line.startIndex, to: zone.lowerBound), line.distance(from: line.startIndex, to: forwarding.lowerBound))
                }
                continue
            }
            guard let (start, end) = bounds else { continue }
            let chars = Array(line)
            guard chars.count > start else { continue }
            let prefix = String(chars.prefix(start)).split(whereSeparator: \.isWhitespace)
            guard prefix.count >= 3, Int(prefix[1]) != nil, Int(prefix[2]) != nil else { continue }
            let zone = String(chars[start..<min(end, chars.count)]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !zone.isEmpty && zone.caseInsensitiveCompare("N/A") != .orderedSame && zone != "-" { tableZones.append(zone) }
        }
        let fromTable = setZones.isEmpty && !tableZones.isEmpty
        let zones = fromTable ? unique(tableZones) : setZones
        return FirewallCLIResult(hostname: names.count == 1 ? names.first : nil, zones: names.count > 1 ? [] : zones,
                                 hasMultipleHostnames: names.count > 1, zonesMayBeTruncated: names.count <= 1 && fromTable)
    }
}
