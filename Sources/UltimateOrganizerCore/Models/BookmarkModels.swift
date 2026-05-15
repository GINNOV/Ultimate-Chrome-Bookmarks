import Foundation

public struct BookmarkSnapshot: Equatable {
    public var roots: [BookmarkFolder]
    public var bookmarks: [BookmarkItem]

    public init(roots: [BookmarkFolder], bookmarks: [BookmarkItem]) {
        self.roots = roots
        self.bookmarks = bookmarks
    }

    public func removingBookmarks(withIDs ids: Set<BookmarkItem.ID>) -> BookmarkSnapshot {
        guard !ids.isEmpty else { return self }

        return BookmarkSnapshot(
            roots: roots.map { $0.removingBookmarks(withIDs: ids) },
            bookmarks: bookmarks.filter { !ids.contains($0.id) }
        )
    }
}

public struct BookmarkImportProgress: Equatable, Sendable {
    public var processedItems: Int
    public var totalItems: Int
    public var currentItemTitle: String?

    public init(processedItems: Int, totalItems: Int, currentItemTitle: String? = nil) {
        self.processedItems = processedItems
        self.totalItems = totalItems
        self.currentItemTitle = currentItemTitle
    }

    public var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return min(1, Double(processedItems) / Double(totalItems))
    }
}

public struct BookmarkFolder: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var path: [String]
    public var children: [BookmarkFolder]
    public var bookmarks: [BookmarkItem]

    public init(
        id: String,
        title: String,
        path: [String],
        children: [BookmarkFolder] = [],
        bookmarks: [BookmarkItem] = []
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.children = children
        self.bookmarks = bookmarks
    }

    public func removingBookmarks(withIDs ids: Set<BookmarkItem.ID>) -> BookmarkFolder {
        BookmarkFolder(
            id: id,
            title: title,
            path: path,
            children: children.map { $0.removingBookmarks(withIDs: ids) },
            bookmarks: bookmarks.filter { !ids.contains($0.id) }
        )
    }
}

public struct BookmarkItem: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var url: URL
    public var folderPath: [String]

    public init(id: String, title: String, url: URL, folderPath: [String]) {
        self.id = id
        self.title = title
        self.url = url
        self.folderPath = folderPath
    }
}

public struct DuplicateMergeResult: Equatable {
    public var unique: [BookmarkItem]
    public var duplicates: [DuplicateBookmark]

    public init(unique: [BookmarkItem], duplicates: [DuplicateBookmark]) {
        self.unique = unique
        self.duplicates = duplicates
    }
}

public struct DuplicateBookmark: Identifiable, Equatable {
    public var id: String { duplicate.id }
    public var duplicate: BookmarkItem
    public var kept: BookmarkItem

    public init(duplicate: BookmarkItem, kept: BookmarkItem) {
        self.duplicate = duplicate
        self.kept = kept
    }
}
