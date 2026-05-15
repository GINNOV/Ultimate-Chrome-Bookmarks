import Foundation

public struct ChromeProfile: Identifiable, Equatable, Sendable {
    public var id: String { directoryName }
    public var directoryName: String
    public var displayName: String?

    public init(directoryName: String, displayName: String?) {
        self.directoryName = directoryName
        self.displayName = displayName
    }

    public var pickerTitle: String {
        guard let displayName, !displayName.isEmpty, displayName != directoryName else {
            return directoryName
        }

        return "\(directoryName) - \(displayName)"
    }
}
