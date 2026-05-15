import Foundation

public struct ChromeBookmarkLocator {
    public init() {}

    public func discoverExistingBookmarkFiles(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> [URL] {
        let baseDirectory = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return Self.bookmarkFileCandidates(applicationSupportDirectory: baseDirectory)
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    public static func bookmarkFileCandidates(applicationSupportDirectory: URL) -> [URL] {
        let chromeDirectory = applicationSupportDirectory
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)

        let profileNames = ["Default"] + (1...5).map { "Profile \($0)" }

        return profileNames.map { profileName in
            chromeDirectory
                .appendingPathComponent(profileName, isDirectory: true)
                .appendingPathComponent("Bookmarks", isDirectory: false)
        }
    }
}
