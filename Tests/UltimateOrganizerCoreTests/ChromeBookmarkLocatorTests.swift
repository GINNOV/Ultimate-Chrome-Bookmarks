import XCTest
@testable import UltimateOrganizerCore

final class ChromeBookmarkLocatorTests: XCTestCase {
    func testDiscoversDefaultAndNamedChromeProfileBookmarkFiles() {
        let appSupport = URL(fileURLWithPath: "/Users/example/Library/Application Support", isDirectory: true)

        let candidates = ChromeBookmarkLocator.bookmarkFileCandidates(applicationSupportDirectory: appSupport)

        XCTAssertEqual(candidates.map(\.path), [
            "/Users/example/Library/Application Support/Google/Chrome/Default/Bookmarks",
            "/Users/example/Library/Application Support/Google/Chrome/Profile 1/Bookmarks",
            "/Users/example/Library/Application Support/Google/Chrome/Profile 2/Bookmarks",
            "/Users/example/Library/Application Support/Google/Chrome/Profile 3/Bookmarks",
            "/Users/example/Library/Application Support/Google/Chrome/Profile 4/Bookmarks",
            "/Users/example/Library/Application Support/Google/Chrome/Profile 5/Bookmarks"
        ])
    }
}
