import XCTest
@testable import UltimateOrganizerCore

final class ChromeProcessDetectorTests: XCTestCase {
    func testDetectsChromeProcessFromProcessNames() {
        XCTAssertTrue(ChromeProcessDetector.isChromeRunning(processNames: [
            "WindowServer",
            "Google Chrome",
            "cfprefsd"
        ]))

        XCTAssertFalse(ChromeProcessDetector.isChromeRunning(processNames: [
            "WindowServer",
            "Safari",
            "cfprefsd"
        ]))
    }
}
