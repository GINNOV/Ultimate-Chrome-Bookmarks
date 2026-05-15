import XCTest
@testable import UltimateOrganizerCore

final class ChromeProfileLocatorTests: XCTestCase {
    func testParsesChromeProfileNamesFromLocalState() throws {
        let data = Data("""
        {
          "profile": {
            "info_cache": {
              "Default": {
                "name": "Personal"
              },
              "Profile 1": {
                "name": "Work"
              }
            }
          }
        }
        """.utf8)

        let profiles = try ChromeProfileLocator.parseProfiles(fromLocalStateData: data)

        XCTAssertEqual(profiles.map(\.directoryName), ["Default", "Profile 1"])
        XCTAssertEqual(profiles.map(\.displayName), ["Personal", "Work"])
        XCTAssertEqual(profiles.map(\.pickerTitle), ["Default - Personal", "Profile 1 - Work"])
    }

    func testFallsBackToDirectoryNameWhenDisplayNameIsMissing() throws {
        let data = Data("""
        {
          "profile": {
            "info_cache": {
              "Default": {}
            }
          }
        }
        """.utf8)

        let profiles = try ChromeProfileLocator.parseProfiles(fromLocalStateData: data)

        XCTAssertEqual(profiles.map(\.pickerTitle), ["Default"])
    }
}
