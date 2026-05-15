import Foundation

public struct ChromeBookmarksParser {
    public init() {}

    public func parse(
        _ data: Data,
        progressHandler: ((BookmarkImportProgress) -> Void)? = nil
    ) throws -> BookmarkSnapshot {
        let document = try JSONDecoder().decode(ChromeBookmarksDocument.self, from: data)
        var bookmarks: [BookmarkItem] = []
        let totalItems = document.roots.orderedNodes.reduce(0) { $0 + countBookmarks(in: $1) }
        var processedItems = 0

        progressHandler?(BookmarkImportProgress(processedItems: 0, totalItems: totalItems))

        let roots = document.roots.orderedNodes.compactMap { rootNode in
            makeFolder(
                from: rootNode,
                parentPath: [],
                bookmarks: &bookmarks,
                totalItems: totalItems,
                processedItems: &processedItems,
                progressHandler: progressHandler
            )
        }

        return BookmarkSnapshot(roots: roots, bookmarks: bookmarks)
    }

    private func makeFolder(
        from node: ChromeBookmarkNode,
        parentPath: [String],
        bookmarks: inout [BookmarkItem],
        totalItems: Int,
        processedItems: inout Int,
        progressHandler: ((BookmarkImportProgress) -> Void)?
    ) -> BookmarkFolder? {
        guard node.type == .folder else { return nil }

        let path = parentPath + [node.name]
        var childFolders: [BookmarkFolder] = []
        var childBookmarks: [BookmarkItem] = []

        for child in node.children ?? [] {
            switch child.type {
            case .folder:
                if let folder = makeFolder(
                    from: child,
                    parentPath: path,
                    bookmarks: &bookmarks,
                    totalItems: totalItems,
                    processedItems: &processedItems,
                    progressHandler: progressHandler
                ) {
                    childFolders.append(folder)
                }
            case .url:
                guard let rawURL = child.url, let url = URL(string: rawURL) else { continue }
                guard shouldImportBookmark(url: url) else {
                    processedItems += 1
                    progressHandler?(BookmarkImportProgress(
                        processedItems: processedItems,
                        totalItems: totalItems,
                        currentItemTitle: child.name
                    ))
                    continue
                }

                let item = BookmarkItem(id: child.id, title: child.name, url: url, folderPath: path)
                childBookmarks.append(item)
                bookmarks.append(item)
                processedItems += 1
                progressHandler?(BookmarkImportProgress(
                    processedItems: processedItems,
                    totalItems: totalItems,
                    currentItemTitle: child.name
                ))
            }
        }

        return BookmarkFolder(
            id: node.id,
            title: node.name,
            path: path,
            children: childFolders,
            bookmarks: childBookmarks
        )
    }

    private func countBookmarks(in node: ChromeBookmarkNode) -> Int {
        switch node.type {
        case .url:
            return 1
        case .folder:
            return (node.children ?? []).reduce(0) { $0 + countBookmarks(in: $1) }
        }
    }

    private func shouldImportBookmark(url: URL) -> Bool {
        let normalized = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return normalized != "chrome://bookmarks"
    }
}

private struct ChromeBookmarksDocument: Decodable {
    var roots: ChromeBookmarkRoots
}

private struct ChromeBookmarkRoots: Decodable {
    var bookmarkBar: ChromeBookmarkNode
    var other: ChromeBookmarkNode
    var synced: ChromeBookmarkNode?

    var orderedNodes: [ChromeBookmarkNode] {
        [bookmarkBar, other] + synced.map { [$0] }.defaultingToEmpty()
    }

    private enum CodingKeys: String, CodingKey {
        case bookmarkBar = "bookmark_bar"
        case other
        case synced
    }
}

private struct ChromeBookmarkNode: Decodable {
    var id: String
    var name: String
    var type: ChromeBookmarkNodeType
    var url: String?
    var children: [ChromeBookmarkNode]?
}

private enum ChromeBookmarkNodeType: String, Decodable {
    case folder
    case url
}

private extension Optional where Wrapped == [ChromeBookmarkNode] {
    func defaultingToEmpty() -> [ChromeBookmarkNode] {
        self ?? []
    }
}
