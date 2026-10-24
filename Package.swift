// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TicketOrganizer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TicketOrganizer", targets: ["TicketOrganizer"])],
    targets: [.executableTarget(name: "TicketOrganizer")]
)
