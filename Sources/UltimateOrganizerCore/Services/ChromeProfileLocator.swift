import Foundation

public struct ChromeProfileLocator {
    public init() {}

    public func discoverProfiles(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> [ChromeProfile] {
        let baseDirectory = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let localStateFile = baseDirectory
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("Local State", isDirectory: false)

        guard let data = try? Data(contentsOf: localStateFile),
              let profiles = try? Self.parseProfiles(fromLocalStateData: data),
              !profiles.isEmpty else {
            return Self.defaultProfiles
        }

        return profiles
    }

    public static func parseProfiles(fromLocalStateData data: Data) throws -> [ChromeProfile] {
        let localState = try JSONDecoder().decode(ChromeLocalState.self, from: data)

        return localState.profile.infoCache
            .map { directoryName, cachedProfile in
                ChromeProfile(directoryName: directoryName, displayName: cachedProfile.name)
            }
            .sorted { lhs, rhs in
                profileSortKey(lhs.directoryName) < profileSortKey(rhs.directoryName)
            }
    }

    public static var defaultProfiles: [ChromeProfile] {
        let directoryNames = ["Default"] + (1...5).map { "Profile \($0)" }
        return directoryNames.map { ChromeProfile(directoryName: $0, displayName: nil) }
    }

    private static func profileSortKey(_ directoryName: String) -> Int {
        if directoryName == "Default" {
            return 0
        }

        guard directoryName.hasPrefix("Profile "),
              let number = Int(directoryName.dropFirst("Profile ".count)) else {
            return Int.max
        }

        return number
    }
}

private struct ChromeLocalState: Decodable {
    var profile: ChromeLocalStateProfile
}

private struct ChromeLocalStateProfile: Decodable {
    var infoCache: [String: ChromeCachedProfile]

    private enum CodingKeys: String, CodingKey {
        case infoCache = "info_cache"
    }
}

private struct ChromeCachedProfile: Decodable {
    var name: String?
}
