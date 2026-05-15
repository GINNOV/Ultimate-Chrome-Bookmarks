import XCTest
@testable import UltimateOrganizer
@testable import UltimateOrganizerCore

@MainActor
final class BookmarkLibraryStoreTests: XCTestCase {
    func testBookmarkSearchMatchesEveryReviewField() throws {
        let bookmark = BookmarkItem(
            id: "manual",
            title: "Original title",
            url: try XCTUnwrap(URL(string: "https://example.com/article?tag=swift")),
            folderPath: ["Bookmarks Bar", "Original"]
        )
        let store = BookmarkLibraryStore()
        store.setProposedTitle("Manual title", for: bookmark)
        store.setProposedFolderText("Bookmarks Bar / Manual", for: bookmark)

        XCTAssertEqual(store.bookmarks([bookmark], matching: "original").map(\.id), ["manual"])
        XCTAssertEqual(store.bookmarks([bookmark], matching: "manual title").map(\.id), ["manual"])
        XCTAssertEqual(store.bookmarks([bookmark], matching: "tag=swift").map(\.id), ["manual"])
        XCTAssertEqual(store.bookmarks([bookmark], matching: "Bookmarks Bar / Manual").map(\.id), ["manual"])
        XCTAssertEqual(store.bookmarks([bookmark], matching: "missing"), [])
    }

    func testStartProcessingPreservesManualEdits() async throws {
        let bookmark = BookmarkItem(
            id: "manual",
            title: "Original title",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            folderPath: ["Bookmarks Bar", "Original"]
        )
        let store = BookmarkLibraryStore()
        store.snapshot = BookmarkSnapshot(
            roots: [
                BookmarkFolder(
                    id: "root",
                    title: "Bookmarks Bar",
                    path: ["Bookmarks Bar"],
                    bookmarks: [bookmark]
                )
            ],
            bookmarks: [bookmark]
        )
        store.state = .loaded
        store.setProposedTitle("Manual title", for: bookmark)
        store.setProposedFolderText("Bookmarks Bar / Manual", for: bookmark)

        let previousEndpoint = UserDefaults.standard.object(forKey: "ollamaEndpoint")
        let previousTimeout = UserDefaults.standard.object(forKey: "ollamaTimeout")
        defer {
            restoreUserDefault(previousEndpoint, forKey: "ollamaEndpoint")
            restoreUserDefault(previousTimeout, forKey: "ollamaTimeout")
        }

        UserDefaults.standard.set("http://127.0.0.1:1", forKey: "ollamaEndpoint")
        UserDefaults.standard.set(0.001, forKey: "ollamaTimeout")
        store.startProcessing()

        let deadline = Date().addingTimeInterval(2)
        while store.state == .processing, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.proposedTitle(for: bookmark), "Manual title")
        XCTAssertEqual(store.proposedFolderPath(for: bookmark), ["Bookmarks Bar", "Manual"])
        XCTAssertEqual(store.enrichmentStatus(for: bookmark), .edited)
    }

    private func restoreUserDefault(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
