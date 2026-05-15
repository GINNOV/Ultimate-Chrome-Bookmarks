import XCTest
@testable import UltimateOrganizerCore

final class DuplicateMergeTests: XCTestCase {
    func testKeepsFirstBookmarkForEachCanonicalURL() throws {
        let bookmarks = [
            BookmarkItem(id: "1", title: "Example", url: try XCTUnwrap(URL(string: "https://example.com/")), folderPath: ["A"]),
            BookmarkItem(id: "2", title: "Example Duplicate", url: try XCTUnwrap(URL(string: "https://example.com")), folderPath: ["B"]),
            BookmarkItem(id: "3", title: "Swift", url: try XCTUnwrap(URL(string: "https://swift.org")), folderPath: ["A"])
        ]

        let result = DuplicateBookmarkMerger().merge(bookmarks)

        XCTAssertEqual(result.unique.map(\.id), ["1", "3"])
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(result.duplicates[0].duplicate.id, "2")
        XCTAssertEqual(result.duplicates[0].kept.id, "1")
    }
}
