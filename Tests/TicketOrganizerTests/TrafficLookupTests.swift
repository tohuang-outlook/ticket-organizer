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
        try store.replace(kind: .interface, with: [])
        XCTAssertEqual(NetworkInventory(url: url).records, route)
    }
}
