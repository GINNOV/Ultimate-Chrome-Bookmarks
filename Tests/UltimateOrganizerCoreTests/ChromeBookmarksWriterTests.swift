import XCTest
@testable import UltimateOrganizerCore

final class ChromeBookmarksWriterTests: XCTestCase {
    func testAppliesTitleUpdatesAndRemovesDeletedBookmarks() throws {
        let updatedData = try ChromeBookmarksWriter().applyChanges(
            to: bookmarksData,
            keepingBookmarkIDs: ["1"],
            proposedTitles: ["1": "New Title"]
        )
        let snapshot = try ChromeBookmarksParser().parse(updatedData)
        let object = try JSONSerialization.jsonObject(with: updatedData) as? [String: Any]

        XCTAssertEqual(snapshot.bookmarks.map(\.id), ["1"])
        XCTAssertEqual(snapshot.bookmarks[0].title, "New Title")
        XCTAssertEqual(snapshot.bookmarks[0].folderPath, ["Bookmarks Bar"])
        XCTAssertEqual(snapshot.roots[0].children.map(\.title), ["Folder"])
        XCTAssertNil(object?["checksum"])
    }

    func testCanPruneEmptyBookmarksBarFoldersWhenPreservationIsDisabled() throws {
        let updatedData = try ChromeBookmarksWriter().applyChanges(
            to: bookmarksData,
            keepingBookmarkIDs: ["1"],
            proposedTitles: ["1": "New Title"],
            preserveBookmarksBarFolders: false
        )
        let snapshot = try ChromeBookmarksParser().parse(updatedData)

        XCTAssertEqual(snapshot.bookmarks.map(\.id), ["1"])
        XCTAssertTrue(snapshot.roots[0].children.isEmpty)
    }

    private var bookmarksData: Data {
        Data("""
        {
          "checksum": "old-checksum",
          "roots": {
            "bookmark_bar": {
              "children": [
                {
                  "id": "1",
                  "name": "Old Title",
                  "type": "url",
                  "url": "https://example.com"
                },
                {
                  "children": [
                    {
                      "id": "2",
                      "name": "Delete Me",
                      "type": "url",
                      "url": "https://delete.example"
                    }
                  ],
                  "id": "folder",
                  "name": "Folder",
                  "type": "folder"
                }
              ],
              "id": "bar",
              "name": "Bookmarks Bar",
              "type": "folder"
            },
            "other": {
              "children": [],
              "id": "other",
              "name": "Other Bookmarks",
              "type": "folder"
            }
          },
          "version": 1
        }
        """.utf8)
    }
}
