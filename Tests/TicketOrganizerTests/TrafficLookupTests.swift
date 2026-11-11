import XCTest
@testable import TicketOrganizer

final class TrafficLookupTests: XCTestCase {
    func testCSVQuotedFieldsNewlinesAndMalformedInput() throws {
        let table = try CSVTable(text: "\u{feff}Firewall,Subnet,Zone\r\n\"fw,1\",10.1.0.1/24,\"inside\nzone\"\r\n")
        XCTAssertEqual(table.rows, [["fw,1", "10.1.0.1/24", "inside\nzone"]])
        XCTAssertThrowsError(try CSVTable(text: "a,b\n\"broken,field"))
    }
    func testIPv4CIDRBoundariesAndSubnetContainment() throws {
        let network = try XCTUnwrap(IPv4Network("10.1.2.7/24"))
        XCTAssertEqual(network.cidr, "10.1.2.0/24")
        XCTAssertTrue(network.contains(try XCTUnwrap(IPv4Network("10.1.2.255"))))
        XCTAssertFalse(network.contains(try XCTUnwrap(IPv4Network("10.1.3.0"))))
        XCTAssertFalse(network.contains(try XCTUnwrap(IPv4Network("10.1.0.0/16"))))
        XCTAssertTrue(try XCTUnwrap(IPv4Network("0.0.0.0/0")).contains(network))
        XCTAssertNil(IPv4Network("10.1.256.1/24"))
        XCTAssertNil(IPv4Network("10.1.2.3/33"))
    }
    func testImportMappingAndLongestRoutePerFirewall() throws {
        let table = try CSVTable(text: "Hostname,Destination,Virtual Router,Next Hop\nfw1,10.0.0.0/8,vr1,10.1.1.1\nfw1,10.2.0.0/16,vr1,10.1.1.2\nfw1,10.2.0.0/16,vr1,10.1.1.3\nfw2,10.0.0.0/8,vr2,10.2.2.2\nfw3,bad,vr1,none\n")
        let report = NetworkColumnMap.suggest(table.headers, kind: .route).records(from: table, kind: .route, source: "routes.csv")
        XCTAssertEqual(report.skippedRows, [6])
        let matches = try XCTUnwrap(NetworkLookup.matches("10.2.3.4", records: report.records))
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(Set(matches.map(\.nextHop)), Set(["10.1.1.2", "10.1.1.3", "10.2.2.2"]))
        XCTAssertNil(NetworkLookup.matches("not an IP", records: report.records))
    }
    func testInterfaceColumnsAndManualFirewallName() throws {
        let table = try CSVTable(text: "name,parent,kind,vsys,virtual_router,zone,tag,ip_addresses,comment\nae1.10,ae1,ae.subif,vsys1,MAIN_VR,INSIDE,10,10.20.30.1/24,example\nae1,,ae,vsys1,,,,,\n")
        let map = NetworkColumnMap.suggest(table.headers, kind: .interface)
        let report = map.records(from: table, kind: .interface, source: "interfaces.csv", firewallName: " FW01 ", managementIP: " 192.0.2.10 ")
        XCTAssertEqual(report.records.count, 1)
        XCTAssertEqual(report.records[0].firewall, "FW01")
        XCTAssertEqual(report.records[0].managementIP, "192.0.2.10")
        XCTAssertEqual(report.records[0].interface, "ae1.10")
        XCTAssertEqual(report.records[0].zone, "INSIDE")
        XCTAssertEqual(report.records[0].router, "MAIN_VR")
        XCTAssertEqual(report.skippedRows, [3])
        XCTAssertEqual(NetworkLookup.matches("10.20.30.25", records: report.records)?.count, 1)
        let data = try JSONEncoder().encode(report.records[0])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "managementIP")
        XCTAssertNil(try JSONDecoder().decode(NetworkRecord.self, from: JSONSerialization.data(withJSONObject: legacy)).managementIP)
    }
    @MainActor func testInventoryImportPersistsAndReplacesOnlyOneKind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("network.json")
        let store = NetworkInventory(url: url)
        let table = try CSVTable(text: "firewall,subnet\nfw1,10.1.0.0/16\n")
        let interface = NetworkColumnMap.suggest(table.headers, kind: .interface).records(from: table, kind: .interface, source: "interfaces.csv").records
        let route = NetworkColumnMap.suggest(table.headers, kind: .route).records(from: table, kind: .route, source: "routes.csv").records
        try store.replace(kind: .interface, with: interface)
        try store.replace(kind: .route, with: route)
        var otherFirewall = try XCTUnwrap(interface.first)
        otherFirewall.firewall = "fw2"
        try store.replace(kind: .interface, with: [otherFirewall])
        var updated = try XCTUnwrap(interface.first)
        updated.zone = "new zone"
        try store.replace(kind: .interface, with: [updated])
        let reloaded = NetworkInventory(url: url).records
        XCTAssertEqual(reloaded.count, 3)
        XCTAssertTrue(reloaded.contains(route[0]))
        XCTAssertTrue(reloaded.contains(otherFirewall))
        XCTAssertTrue(reloaded.contains(updated))
    }
}
