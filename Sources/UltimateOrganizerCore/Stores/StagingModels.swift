import Foundation
import SwiftData

@Model
public final class StagedFolder {
    public var id: String
    public var name: String
    public var parentPath: [String]

    @Relationship(deleteRule: .cascade)
    public var bookmarks: [StagedBookmark]

    public init(id: String, name: String, parentPath: [String], bookmarks: [StagedBookmark] = []) {
        self.id = id
        self.name = name
        self.parentPath = parentPath
        self.bookmarks = bookmarks
    }
}

@Model
public final class StagedBookmark {
    public var id: String
    public var originalTitle: String
    public var proposedTitle: String
    public var urlString: String
    public var originalFolderPath: [String]
    public var proposedFolderPath: [String]

    public init(
        id: String,
        originalTitle: String,
        proposedTitle: String,
        urlString: String,
        originalFolderPath: [String],
        proposedFolderPath: [String]
    ) {
        self.id = id
        self.originalTitle = originalTitle
        self.proposedTitle = proposedTitle
        self.urlString = urlString
        self.originalFolderPath = originalFolderPath
        self.proposedFolderPath = proposedFolderPath
    }
}
