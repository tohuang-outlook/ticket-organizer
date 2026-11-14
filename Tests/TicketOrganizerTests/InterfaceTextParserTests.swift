import XCTest
@testable import TicketOrganizer

final class InterfaceTextParserTests: XCTestCase {
    func testProvidedConfigurationWhenAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["TICKET_INTERFACE_SAMPLE"] else { return }
        let table = try InterfaceTextParser.parse(String(contentsOfFile: path, encoding: .utf8))
        XCTAssertGreaterThan(table.rows.count, 1)
        XCTAssertTrue(table.rows.contains { $0[0].hasPrefix("BDI") && !$0[3].isEmpty })
    }
    func testCiscoConfigurationWithTimestampsAndSecondaryAddress() throws {
        let input = """
        123456.000: hostname example
        123456.001: interface GigabitEthernet0
        123456.002:  vrf forwarding MGMT
        123456.003:  ip address 10.1.2.3 255.255.255.0
        123456.004:  ip address 10.2.0.1 255.255.0.0 secondary
        123456.005:  shutdown
        123456.006: !
        123456.007: interface Loopback0
        123456.008:  ip address 192.0.2.1 255.255.255.255
        123456.009: !
        """
        let table = try InterfaceTextParser.parse(input)
        let report = NetworkColumnMap.suggest(table.headers, kind: .interface).records(from: table, kind: .interface, source: "test.txt", firewallName: "router")
        XCTAssertEqual(report.records.map(\.subnet), ["10.1.2.3/24", "10.2.0.1/16", "192.0.2.1/32"])
        XCTAssertEqual(report.records.map(\.router), ["MGMT", "MGMT", ""])
        XCTAssertEqual(report.records.map(\.sourceLine), [4, 5, 9])
        XCTAssertEqual(report.records.first?.interfaceStatus, "Administratively down")
        XCTAssertEqual(NetworkLookup.matches("10.1.2.50", records: report.records)?.count, 1)
    }

    func testPANLogicalTableAndNoZone() throws {
        let input = """
        total configured logical interfaces: 2

        name                      id    vsys zone             forwarding               tag    address
        ------------------------- ----- ---- ---------------- ------------------------ ------ ------------------
        ae1                       16    1                     N/A                      0      N/A
        ae1.16                    1124  1    ucsf_pan_inside  vr:ucsf                  16     10.19.16.1/23
        ae1.22                    1123  1                     vr:ucsf                  22     10.19.22.1/23
        """
        let table = try InterfaceTextParser.parse(input)
        let records = NetworkColumnMap.suggest(table.headers, kind: .interface).records(from: table, kind: .interface, source: "fw.txt", firewallName: "fw").records
        XCTAssertEqual(records.map(\.zone), ["ucsf_pan_inside", ""])
        XCTAssertEqual(records.map(\.router), ["ucsf", "ucsf"])
        XCTAssertEqual(records.first?.sourceLine, 6)
        XCTAssertEqual(records.first?.zoneMayBeTruncated, true)
    }

    func testInvalidMaskAndUnsupportedTextAreRejected() {
        XCTAssertThrowsError(try InterfaceTextParser.parse("interface Ethernet1\n ip address 10.0.0.1 255.0.255.0\n!"))
        XCTAssertThrowsError(try InterfaceTextParser.parse("not interface data"))
    }
}
