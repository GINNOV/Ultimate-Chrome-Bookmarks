import XCTest
@testable import UltimateOrganizer

final class AutoUpdateConfigurationTests: XCTestCase {
    func testDefaultFeedURLPointsAtGitHubPagesAppcastForThisApp() throws {
        XCTAssertEqual(
            AutoUpdateConfiguration.defaultFeedURL,
            URL(string: "https://ginnov.github.io/Ultimate-Chrome-Bookmarks/appcast.xml")
        )
    }
}
