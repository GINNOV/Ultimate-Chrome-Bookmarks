import Sparkle
import SwiftData
import SwiftUI
import UltimateOrganizerCore

@main
struct UltimateOrganizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("useEnrichmentCache") private var useEnrichmentCache = true

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StagedBookmark.self,
            StagedFolder.self
        ])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("Ultimate Bookmarks Organizer") {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ultimate Bookmarks Organizer") {
                    NotificationCenter.default.post(name: .showAboutRequested, object: nil)
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
            }

            CommandGroup(after: .newItem) {
                Button("Reload Chrome Bookmarks") {
                    NotificationCenter.default.post(name: .reloadBookmarksRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandMenu("Processing") {
                Toggle("Use Cache", isOn: $useEnrichmentCache)
                    .onChange(of: useEnrichmentCache) { _, newValue in
                        if !newValue {
                            NotificationCenter.default.post(name: .enrichmentCacheDisabled, object: nil)
                        }
                    }

                Divider()

                Button("Enrich Items") {
                    NotificationCenter.default.post(name: .enrichBookmarksRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}
