import XCTest
@testable import UltimateOrganizerCore

final class BookmarkSnapshotDeletionTests: XCTestCase {
    func testRemovingBookmarksUpdatesFlatListAndFolderTree() throws {
        let keep = BookmarkItem(
            id: "keep",
            title: "Keep",
            url: try XCTUnwrap(URL(string: "https://keep.example")),
            folderPath: ["Bookmarks Bar"]
        )
        let remove = BookmarkItem(
            id: "remove",
            title: "Remove",
            url: try XCTUnwrap(URL(string: "https://remove.example")),
            folderPath: ["Bookmarks Bar"]
        )
        let snapshot = BookmarkSnapshot(
            roots: [
                BookmarkFolder(
                    id: "root",
                    title: "Bookmarks Bar",
                    path: ["Bookmarks Bar"],
                    bookmarks: [keep, remove]
                )
            ],
            bookmarks: [keep, remove]
        )

        let updated = snapshot.removingBookmarks(withIDs: ["remove"])

        XCTAssertEqual(updated.bookmarks.map(\.id), ["keep"])
        XCTAssertEqual(updated.roots[0].bookmarks.map(\.id), ["keep"])
    }
}
