import Foundation

public struct ChromeBookmarksWriter {
    public init() {}

    public func applyChanges(
        to data: Data,
        keepingBookmarkIDs keepIDs: Set<String>,
        proposedTitles: [String: String],
        preserveBookmarksBarFolders: Bool = true
    ) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
        guard var document = object as? [String: Any],
              var roots = document["roots"] as? [String: Any]
        else {
            throw ChromeBookmarksWriterError.invalidDocument
        }

        for rootKey in ["bookmark_bar", "other", "synced"] {
            guard let root = roots[rootKey] as? [String: Any] else { continue }
            roots[rootKey] = rewriteNode(
                root,
                keepingBookmarkIDs: keepIDs,
                proposedTitles: proposedTitles,
                preserveFolders: rootKey == "bookmark_bar" ? preserveBookmarksBarFolders : true
            )
        }

        document["roots"] = roots
        document.removeValue(forKey: "checksum")

        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    private func rewriteNode(
        _ node: [String: Any],
        keepingBookmarkIDs keepIDs: Set<String>,
        proposedTitles: [String: String],
        preserveFolders: Bool
    ) -> [String: Any]? {
        guard let type = node["type"] as? String else { return node }

        if type == "url" {
            guard let id = node["id"] as? String, keepIDs.contains(id) else {
                return nil
            }

            var updatedNode = node
            if let proposedTitle = proposedTitles[id], !proposedTitle.isEmpty {
                updatedNode["name"] = proposedTitle
            }
            return updatedNode
        }

        guard type == "folder" else { return node }

        var updatedNode = node
        if let children = node["children"] as? [[String: Any]] {
            updatedNode["children"] = children.compactMap { child in
                rewriteNode(
                    child,
                    keepingBookmarkIDs: keepIDs,
                    proposedTitles: proposedTitles,
                    preserveFolders: preserveFolders
                )
            }
        }

        guard preserveFolders else {
            let children = updatedNode["children"] as? [[String: Any]] ?? []
            return children.isEmpty ? nil : updatedNode
        }

        return updatedNode
    }
}

public enum ChromeBookmarksWriterError: LocalizedError {
    case invalidDocument

    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The Chrome Bookmarks file could not be decoded."
        }
    }
}
