import XCTest
@testable import GlyCore

final class PackageTests: XCTestCase {
    func testIdentifiersAreConsistent() {
        XCTAssertTrue(GlyIDs.agentMachService.hasPrefix(GlyIDs.appGroup))
        XCTAssertTrue(GlyIDs.appGroup.hasPrefix(GlyIDs.teamID))
    }
}
