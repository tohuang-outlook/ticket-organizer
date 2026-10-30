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
}

enum FirewallCLIParser {
    // These patterns cover PAN-OS 'show system info' and configuration in set format.
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
                           capture(#"^[\t ]*set[\t ]+deviceconfig[\t ]+system[\t ]+hostname[\t ]+(?:"([^"]+)"|(\S+))[\t ]*\r?$"#, groups: [1, 2]))
        let zones = unique(capture(#"^[\t ]*set[\t ]+zone[\t ]+(?:"([^"]+)"|(\S+))(?:[\t ]|\r?$)"#, groups: [1, 2]))
        return FirewallCLIResult(hostname: names.count == 1 ? names.first : nil, zones: names.count > 1 ? [] : zones, hasMultipleHostnames: names.count > 1)
    }
}
