import XCTest
@testable import UltimateOrganizerCore

final class ChromeBookmarksParserTests: XCTestCase {
    func testParsesNestedChromeBookmarkTreeIntoFoldersAndBookmarks() throws {
        let data = Data("""
        {
          "checksum": "abc",
          "roots": {
            "bookmark_bar": {
              "children": [
                {
                  "children": [
                    {
                      "date_added": "13345012345678901",
                      "guid": "bookmark-guid",
                      "id": "3",
                      "name": "Swift.org",
                      "type": "url",
                      "url": "https://swift.org"
                    }
                  ],
                  "date_added": "13345000000000000",
                  "date_modified": "13345011111111111",
                  "guid": "folder-guid",
                  "id": "2",
                  "name": "Development",
                  "type": "folder"
                }
              ],
              "date_added": "13344999999999999",
              "guid": "bar-guid",
              "id": "1",
              "name": "Bookmarks Bar",
              "type": "folder"
            },
            "other": {
              "children": [],
              "id": "4",
              "name": "Other Bookmarks",
              "type": "folder"
            },
            "synced": {
              "children": [],
              "id": "5",
              "name": "Mobile Bookmarks",
              "type": "folder"
            }
          },
          "version": 1
        }
        """.utf8)

        let snapshot = try ChromeBookmarksParser().parse(data)

        XCTAssertEqual(snapshot.roots.count, 3)
        XCTAssertEqual(snapshot.bookmarks.count, 1)
        XCTAssertEqual(snapshot.bookmarks[0].title, "Swift.org")
        XCTAssertEqual(snapshot.bookmarks[0].url.absoluteString, "https://swift.org")
        XCTAssertEqual(snapshot.bookmarks[0].folderPath, ["Bookmarks Bar", "Development"])
    }

    func testReportsDeterminateProgressWhileParsingBookmarks() throws {
        let data = Data("""
        {
          "roots": {
            "bookmark_bar": {
              "children": [
                {
                  "date_added": "1",
                  "guid": "one",
                  "id": "1",
                  "name": "One",
                  "type": "url",
                  "url": "https://one.example"
                },
                {
                  "date_added": "2",
                  "guid": "two",
                  "id": "2",
                  "name": "Two",
                  "type": "url",
                  "url": "https://two.example"
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
        var updates: [BookmarkImportProgress] = []

        _ = try ChromeBookmarksParser().parse(data) { progress in
            updates.append(progress)
        }

        XCTAssertEqual(updates.map(\.processedItems), [0, 1, 2])
        XCTAssertEqual(updates.map(\.totalItems), [2, 2, 2])
        XCTAssertEqual(updates.last?.fractionCompleted, 1)
    }

    func testSkipsChromeBookmarksManagerShortcut() throws {
        let data = Data("""
        {
          "roots": {
            "bookmark_bar": {
              "children": [
                {
                  "id": "1",
                  "name": "Bookmarks",
                  "type": "url",
                  "url": "chrome://bookmarks/"
                },
                {
                  "id": "2",
                  "name": "Example",
                  "type": "url",
                  "url": "https://example.com"
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

        let snapshot = try ChromeBookmarksParser().parse(data)

        XCTAssertEqual(snapshot.bookmarks.map(\.url.absoluteString), ["https://example.com"])
        XCTAssertEqual(snapshot.roots[0].bookmarks.map(\.title), ["Example"])
    }

    func testUnknownTotalProgressIsNotComplete() {
        let progress = BookmarkImportProgress(processedItems: 0, totalItems: 0)

        XCTAssertEqual(progress.fractionCompleted, 0)
    }
}
