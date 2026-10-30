import XCTest
@testable import TicketOrganizer

final class FirewallCatalogTests: XCTestCase {
    func testPANOSExtractionRecognizesOnlyExplicitLines() {
        let result = FirewallCLIParser.parse("""
        hostname: edge-fw01
        set deviceconfig system hostname edge-fw01
        set zone Trust network layer3 ethernet1/1
        set zone Trust network enable-user-identification yes
        set zone "Guest Zone" network layer3 ethernet1/2
        set network profiles zone-protection-profile ignored flood tcp-syn enable yes
        """)
        XCTAssertEqual(result.hostname, "edge-fw01")
        XCTAssertEqual(result.zones, ["Trust", "Guest Zone"])
        XCTAssertFalse(result.hasMultipleHostnames)
        let unsupported = FirewallCLIParser.parse("set zone\nset unrelated information\nset zone <name> network layer3")
        XCTAssertNil(unsupported.hostname)
        XCTAssertTrue(unsupported.zones.isEmpty)
    }

    func testMultipleHostnamesDoNotProduceAmbiguousImport() {
        let result = FirewallCLIParser.parse("hostname: fw-a\nhostname: fw-b\nset zone Trust network layer3 ethernet1/1")
        XCTAssertTrue(result.hasMultipleHostnames)
        XCTAssertNil(result.hostname)
        XCTAssertTrue(result.zones.isEmpty)
    }

    @MainActor
    func testCatalogPersistsRenamesAndBackupRestoresWithoutChangingTicketIDs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tickets.json")
        let store = TicketStore(url: url)
        XCTAssertEqual(store.firewalls.count, 5)
        var ticket = TicketNote(ritm: "RITM1", chg: "", title: "", body: "", stage: .draft, priority: .low, owner: "")
        ticket.trafficFlow = ["FW01"]
        ticket.firewallZones = [["zone 2", "zone 1"]]
        try store.add(ticket)
        var firewall = try XCTUnwrap(store.firewalls.first)
        firewall.name = "Edge Firewall"
        firewall.deviceGroup = "QUINCY"
        firewall.zones = ["inside", "outside"]
        firewall.isActive = false
        try store.saveFirewall(firewall, isNew: false)
        let reopened = TicketStore(url: url)
        XCTAssertEqual(reopened.firewalls.first, firewall)
        XCTAssertEqual(reopened.notes.first?.trafficFlow, ["FW01"])
        XCTAssertEqual(reopened.notes.first?.firewallZones, [["zone 2", "zone 1"]])
        XCTAssertEqual(TicketNote.togglingZone("inside", in: []), ["inside"])
        let backup = folder.appendingPathComponent("backup.json")
        try store.exportBackup(to: backup)
        firewall.name = "Changed"
        try store.saveFirewall(firewall, isNew: false)
        _ = try store.restoreBackup(from: backup)
        XCTAssertEqual(store.firewalls.first?.name, "Edge Firewall")
        XCTAssertEqual(store.notes.first?.trafficFlow, ["FW01"])
    }

    @MainActor
    func testCatalogRejectsDuplicateNamesAndZonesWithoutChangingData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let before = store.firewalls
        let duplicate = FirewallDefinition(id: "new", name: "fw01", deviceGroup: "", zones: [], isActive: true)
        XCTAssertThrowsError(try store.saveFirewall(duplicate, isNew: true))
        let duplicateZones = FirewallDefinition(id: "new", name: "New", deviceGroup: "", zones: ["Trust", "trust"], isActive: true)
        XCTAssertThrowsError(try store.saveFirewall(duplicateZones, isNew: true))
        XCTAssertEqual(store.firewalls, before)
    }

    @MainActor
    func testBackupRestoresDefaultCatalogAfterLaterChanges() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TicketStore(url: folder.appendingPathComponent("tickets.json"))
        let backup = folder.appendingPathComponent("backup.json")
        try store.exportBackup(to: backup)
        let extra = FirewallDefinition(id: "FW06", name: "FW06", deviceGroup: "New", zones: [], isActive: true)
        try store.saveFirewall(extra, isNew: true)
        XCTAssertEqual(store.firewalls.count, 6)
        _ = try store.restoreBackup(from: backup)
        XCTAssertEqual(store.firewalls, FirewallDefinition.placeholders)
    }
}
