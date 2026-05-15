import Foundation

public struct DuplicateBookmarkMerger {
    public init() {}

    public func merge(_ bookmarks: [BookmarkItem]) -> DuplicateMergeResult {
        var seen: [String: BookmarkItem] = [:]
        var unique: [BookmarkItem] = []
        var duplicates: [DuplicateBookmark] = []

        for bookmark in bookmarks {
            let key = canonicalKey(for: bookmark.url)
            if let kept = seen[key] {
                duplicates.append(DuplicateBookmark(duplicate: bookmark, kept: kept))
            } else {
                seen[key] = bookmark
                unique.append(bookmark)
            }
        }

        return DuplicateMergeResult(unique: unique, duplicates: duplicates)
    }

    private func canonicalKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        if components.path == "/" {
            components.path = ""
        }

        return components.string ?? url.absoluteString.lowercased()
    }
}
