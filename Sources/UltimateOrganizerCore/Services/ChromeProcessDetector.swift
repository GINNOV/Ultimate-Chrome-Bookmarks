import Foundation

public struct ChromeProcessDetector {
    public init() {}

    public func isChromeRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Google Chrome"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0
    }

    public static func isChromeRunning(processNames: [String]) -> Bool {
        processNames.contains { processName in
            processName.hasSuffix("/Google Chrome") || processName == "Google Chrome"
        }
    }
}
