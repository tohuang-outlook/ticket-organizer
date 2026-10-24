import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("iCloud profile validation failed: " + message + "\n").utf8))
    exit(1)
}

// Input is a decoded Apple provisioning profile, not credentials or a certificate.
guard CommandLine.arguments.count == 5 else { fail("Expected profile.plist, output.entitlements, container ID, environment") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let container = CommandLine.arguments[3]
let environment = CommandLine.arguments[4]
let profile = try PropertyListSerialization.propertyList(from: Data(contentsOf: input), format: nil) as? [String: Any]
guard let profile, let expiry = profile["ExpirationDate"] as? Date, expiry > Date(),
      let entitlements = profile["Entitlements"] as? [String: Any],
      let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String], containers.contains(container),
      let services = entitlements["com.apple.developer.icloud-services"] as? [String], services.contains("CloudKit"),
      let teams = profile["TeamIdentifier"] as? [String], let team = teams.first else {
    fail("Profile is expired or does not grant the required CloudKit container and service")
}
let appKey = entitlements["com.apple.application-identifier"] != nil ? "com.apple.application-identifier" : "application-identifier"
let allowedEnvironment = (entitlements["com.apple.developer.icloud-container-environment"] as? String) == environment ||
    (entitlements["com.apple.developer.icloud-container-environment"] as? [String])?.contains(environment) == true
guard let appID = entitlements[appKey] as? String, appID.hasSuffix(".com.tohuang.ticket-organizer"),
      ["Development", "Production"].contains(environment),
      allowedEnvironment else {
    fail("Profile must match com.tohuang.ticket-organizer and the requested iCloud environment")
}
let signedEntitlements: [String: Any] = [
    appKey: appID,
    "com.apple.developer.team-identifier": team,
    "com.apple.developer.icloud-container-identifiers": [container],
    "com.apple.developer.icloud-services": ["CloudKit"],
    "com.apple.developer.icloud-container-environment": environment
]
let data = try PropertyListSerialization.data(fromPropertyList: signedEntitlements, format: .xml, options: 0)
try data.write(to: output, options: .atomic)
print("Validated iCloud provisioning profile for \(environment)")
