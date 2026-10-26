import XCTest
@testable import WorkDashCore

final class PackageTests: XCTestCase {
    func testIdentifiersAreConsistent() {
        XCTAssertTrue(WorkDashIDs.agentMachService.hasPrefix(WorkDashIDs.appGroup))
        XCTAssertTrue(WorkDashIDs.appGroup.hasPrefix(WorkDashIDs.teamID))
    }
}
