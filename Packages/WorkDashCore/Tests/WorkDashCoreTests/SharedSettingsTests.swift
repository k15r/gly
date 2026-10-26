import XCTest
@testable import WorkDashCore

final class SharedSettingsTests: XCTestCase {
    var suiteNames: [String] = []
    func suite() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }
    override func tearDown() { suiteNames.forEach { UserDefaults().removePersistentDomain(forName: $0) } }

    func testDefaults() {
        let s = SharedSettings(defaults: suite())
        XCTAssertFalse(s.httpEnabled)
        XCTAssertEqual(s.httpPort, 47615)
        XCTAssertEqual(s.hiddenCalendarIDs, [])
        XCTAssertEqual(s.httpAllowedOrigins, [])
        XCTAssertTrue(s.deviceID.hasPrefix("mac-"))
        XCTAssertEqual(s.deviceID, s.deviceID, "stable once created")
    }

    func testMigrationCopiesOnlyMissingKeys() {
        let old = suite()
        old.set("mac-old111", forKey: "deviceID")
        old.set(["cal-a"], forKey: "hiddenCalendarIDs")
        let fresh = SharedSettings(defaults: suite())
        fresh.migrate(from: old)
        XCTAssertEqual(fresh.deviceID, "mac-old111")
        XCTAssertEqual(fresh.hiddenCalendarIDs, ["cal-a"])

        let existing = SharedSettings(defaults: suite())
        existing.defaults.set("mac-new222", forKey: "deviceID")
        existing.hiddenCalendarIDs = []
        existing.migrate(from: old)
        XCTAssertEqual(existing.deviceID, "mac-new222", "group value wins")
        XCTAssertEqual(existing.hiddenCalendarIDs, [], "an explicitly empty set isn't overwritten")
    }

    func testTokenIs32RandomBytesBase64URL() {
        let s = SharedSettings(defaults: suite())
        let t = s.httpToken
        XCTAssertEqual(t, s.httpToken, "stable until regenerated")
        XCTAssertEqual(t.count, 43)                              // 32 bytes → 43 base64url chars, no padding
        XCTAssertNil(t.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(s.regenerateHTTPToken(), t)
    }
}

extension SharedSettingsTests {
    func testPlanningDefaults() {
        let s = SharedSettings(defaults: suite())
        XCTAssertEqual(s.workingHours, WorkingHours(startMinute: 540, endMinute: 1020))
        XCTAssertEqual(s.horizonDays, 5)
        XCTAssertEqual(s.effortSizes[.l], 480, "default sizes: L = one working day")
        XCTAssertEqual(s.effortSizes[.xl], 1440)
    }

    func testConfiguredSizeAndDerivedDefaults() {
        let s = SharedSettings(defaults: suite())
        s.setEffortMinutes(180, for: .m)
        XCTAssertEqual(s.effortSizes[.m], 180, "configured size")
        s.workingHours = WorkingHours(startMinute: 480, endMinute: 960)
        XCTAssertEqual(s.effortSizes[.l], 480)
        s.workingHours = WorkingHours(startMinute: 480, endMinute: 840)
        XCTAssertEqual(s.effortSizes[.l], 360, "L follows the working day while unset")
        s.setEffortMinutes(nil, for: .m)
        XCTAssertEqual(s.effortSizes[.m], 240, "reset to default")
        s.horizonDays = 14
        XCTAssertEqual(s.horizonDays, 14)
    }
}
