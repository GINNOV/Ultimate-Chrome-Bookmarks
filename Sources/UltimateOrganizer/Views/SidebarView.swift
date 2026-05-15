import SwiftUI
import UltimateOrganizerCore

struct SidebarView: View {
    @Binding var selection: String
    var store: BookmarkLibraryStore
    @State private var chromeProfiles = ChromeProfileLocator.defaultProfiles

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item.rawValue)
                }
            }

            Section("Chrome") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProfileTitle)
                        .lineLimit(1)
                    Text("\(store.snapshot.bookmarks.count) bookmarks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            chromeProfiles = ChromeProfileLocator().discoverProfiles()
        }
    }

    private var selectedProfileTitle: String {
        guard let profileDirectoryName = store.selectedBookmarkFile?.deletingLastPathComponent().lastPathComponent else {
            return "No profile"
        }

        return chromeProfiles.first { $0.directoryName == profileDirectoryName }?.pickerTitle ?? profileDirectoryName
    }
}
