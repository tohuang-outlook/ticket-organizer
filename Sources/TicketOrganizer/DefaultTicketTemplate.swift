import AppKit

enum DefaultTicketTemplate {
    static let text = """
    —————————————————————————————————
    On Panorama, Device Group: QUINCY_UCSF

    Under OBJECTS > Addresses, add a new shared address object:
    - Name:
    - Type: IP Netmask
    - Address:
    - Shared

    Under POLICIES > Security > Pre Rules, add a new rule:
    - name:
    - Source zone:
    - Source address:
    - Destination zone:
    - Destination address:
    - Service:
    - Action: Allow

    Commit and push to the QUINCY_UCSF device group.


    Backout Plan:

    On panorama, remove the newly created security rule and address object, then commit and push.
    """

    static func richText() -> Data? {
        let font = NSFont.systemFont(ofSize: 16)
        let bold = NSFont.boldSystemFont(ofSize: 16)
        let value = NSMutableAttributedString(string: text, attributes: [.font: font])
        let string = text as NSString
        for phrase in ["On Panorama, Device Group: QUINCY_UCSF", "shared", "QUINCY_UCSF", "Backout Plan:", "panorama"] {
            var remaining = NSRange(location: 0, length: string.length)
            while remaining.length > 0 {
                let found = string.range(of: phrase, options: [], range: remaining)
                if found.location == NSNotFound { break }
                value.addAttribute(.font, value: bold, range: found)
                let next = NSMaxRange(found)
                remaining = NSRange(location: next, length: string.length - next)
            }
        }
        return try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
