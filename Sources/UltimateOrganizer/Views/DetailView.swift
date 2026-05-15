import SwiftUI
import UltimateOrganizerCore
import WebKit

struct DetailView: View {
    var selection: SidebarItem
    var store: BookmarkLibraryStore

    var body: some View {
        switch selection {
        case .overview:
            OverviewView(store: store)
        case .review:
            ReviewView(store: store, bookmarks: store.duplicateResult.unique)
        case .duplicates:
            DuplicatesView(store: store, result: store.duplicateResult)
        case .safety:
            StorageView(store: store)
        }
    }
}

private struct OverviewView: View {
    var store: BookmarkLibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(title: "Bookmark Library", subtitle: store.selectedBookmarkFile?.path ?? "No Chrome bookmark file loaded")

                HStack(spacing: 12) {
                    MetricView(title: "Bookmarks", value: "\(store.snapshot.bookmarks.count)")
                    MetricView(title: "Folders", value: "\(folderCount(in: store.snapshot.roots))")
                    MetricView(title: "Duplicates", value: "\(store.duplicateResult.duplicates.count)")
                }

                GroupBox("Root Folders") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.snapshot.roots) { folder in
                            HStack {
                                Label(folder.title, systemImage: "folder")
                                Spacer()
                                Text("\(bookmarkCount(in: folder))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private func folderCount(in folders: [BookmarkFolder]) -> Int {
        folders.reduce(0) { count, folder in
            count + 1 + folderCount(in: folder.children)
        }
    }

    private func bookmarkCount(in folder: BookmarkFolder) -> Int {
        folder.bookmarks.count + folder.children.reduce(0) { $0 + bookmarkCount(in: $1) }
    }
}

private struct ReviewView: View {
    var store: BookmarkLibraryStore
    var bookmarks: [BookmarkItem]
    @AppStorage("skipDeleteConfirmation") private var skipDeleteConfirmation = false
    @State private var selectedBookmarkIDs = Set<BookmarkItem.ID>()
    @State private var isPreviewVisible = true
    @State private var isShowingDeleteConfirmation = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            SelectionActionBar(
                selectedCount: selectedBookmarkIDs.count,
                protectedSelectedCount: selectedBookmarks.filter { store.isBookmarkProtected($0) }.count,
                isPreviewVisible: $isPreviewVisible,
                protectAction: { store.setBookmarkProtection(true, for: selectedBookmarkIDs) },
                unprotectAction: { store.setBookmarkProtection(false, for: selectedBookmarkIDs) },
                deleteAction: confirmOrDeleteSelectedBookmarks
            )

            HSplitView {
                Table(filteredBookmarks, selection: $selectedBookmarkIDs) {
                    TableColumn("Keep") { bookmark in
                        ProtectionToggle(isProtected: store.isBookmarkProtected(bookmark)) {
                            store.toggleBookmarkProtection(for: bookmark)
                        }
                    }
                    .width(min: 36, ideal: 40, max: 44)

                    TableColumn("AI") { bookmark in
                        EnrichmentStatusIcon(status: store.enrichmentStatus(for: bookmark))
                    }
                    .width(min: 26, ideal: 28, max: 32)

                    TableColumn("Current") { bookmark in
                        Text(bookmark.title)
                            .lineLimit(1)
                    }

                    TableColumn("Proposed") { bookmark in
                        EditableProposedTitleCell(store: store, bookmark: bookmark)
                    }

                    TableColumn("Current Folder") { bookmark in
                        FolderPathCell(folderPath: bookmark.folderPath)
                    }

                    TableColumn("Destination Folder") { bookmark in
                        EditableDestinationFolderCell(store: store, bookmark: bookmark)
                    }

                    TableColumn("URL") { bookmark in
                        BookmarkURLLink(url: bookmark.url)
                    }
                }
                .frame(minWidth: 520)

                if isPreviewVisible {
                    BookmarkPreviewPanel(
                        store: store,
                        selectedBookmarks: selectedBookmarks,
                        proposedTitle: selectedBookmarks.count == 1 ? store.proposedTitle(for: selectedBookmarks[0]) : nil,
                        proposedFolderPath: selectedBookmarks.count == 1 ? store.proposedFolderPath(for: selectedBookmarks[0]) : nil,
                        isProtected: selectedBookmarks.count == 1 ? store.isBookmarkProtected(selectedBookmarks[0]) : false,
                        collapseAction: { isPreviewVisible = false }
                    )
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
                }
            }
        }
        .confirmationDialog(
            "Delete selected bookmarks?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationButtonTitle, role: .destructive) {
                deleteSelectedBookmarks()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .onChange(of: filteredBookmarks.map(\.id)) { _, visibleIDs in
            selectedBookmarkIDs.formIntersection(Set(visibleIDs))
        }
    }

    private var filteredBookmarks: [BookmarkItem] {
        store.bookmarks(bookmarks, matching: searchText)
    }

    private var selectedBookmarks: [BookmarkItem] {
        filteredBookmarks.filter { selectedBookmarkIDs.contains($0.id) }
    }

    private var selectedDeletableBookmarkIDs: Set<BookmarkItem.ID> {
        Set(selectedBookmarks.filter { !store.isBookmarkProtected($0) }.map(\.id))
    }

    private var deleteConfirmationButtonTitle: String {
        selectedDeletableBookmarkIDs.count == 1 ? "Delete Bookmark" : "Delete \(selectedDeletableBookmarkIDs.count) Bookmarks"
    }

    private var deleteConfirmationMessage: String {
        "This removes the selected unprotected bookmarks from the working set. The change is written to Chrome only when you apply changes."
    }

    private func confirmOrDeleteSelectedBookmarks() {
        guard !selectedDeletableBookmarkIDs.isEmpty else { return }

        if DeletionConfirmationPolicy.shouldConfirm(skipConfirmation: skipDeleteConfirmation) {
            isShowingDeleteConfirmation = true
        } else {
            deleteSelectedBookmarks()
        }
    }

    private func deleteSelectedBookmarks() {
        store.deleteBookmarks(withIDs: selectedDeletableBookmarkIDs)
        selectedBookmarkIDs.removeAll()
    }
}

private struct DuplicatesView: View {
    var store: BookmarkLibraryStore
    var result: DuplicateMergeResult
    @AppStorage("skipDeleteConfirmation") private var skipDeleteConfirmation = false
    @State private var selectedDuplicateIDs = Set<DuplicateBookmark.ID>()
    @State private var pendingDeleteAction: DuplicateDeleteAction?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Duplicate Cleanup")
                            .font(.headline)
                        Text("Each row is a duplicate bookmark that can be removed. The app keeps the bookmark shown in the Keep column.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(result.duplicates.count) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 10) {
                    Text(selectedDuplicateIDs.isEmpty ? "Select rows to remove only those duplicates." : "\(selectedDuplicateIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button(role: .destructive) {
                        confirmOrDeleteDuplicates(.selected)
                    } label: {
                        Label("Remove Selected Duplicates", systemImage: "trash")
                    }
                    .disabled(selectedDuplicateIDs.isEmpty)
                    .help("Remove the selected duplicate bookmarks and keep their paired originals")

                    Button(role: .destructive) {
                        confirmOrDeleteDuplicates(.all)
                    } label: {
                        Label("Remove All Duplicates", systemImage: "trash.slash")
                    }
                    .disabled(result.duplicates.isEmpty)
                    .help("Remove every detected duplicate bookmark and keep the originals")
                }
            }
            .padding()
            .background(.bar)

            Table(result.duplicates, selection: $selectedDuplicateIDs) {
                TableColumn("Remove") { duplicate in
                    Text(duplicate.duplicate.title)
                        .lineLimit(1)
                }
                TableColumn("Keep") { duplicate in
                    Text(duplicate.kept.title)
                        .lineLimit(1)
                }
                TableColumn("URL") { duplicate in
                    BookmarkURLLink(url: duplicate.duplicate.url)
                }
            }
        }
        .confirmationDialog(
            duplicateConfirmationTitle,
            isPresented: duplicateDeleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(duplicateConfirmationButtonTitle, role: .destructive) {
                performPendingDuplicateDelete()
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        } message: {
            Text(duplicateConfirmationMessage)
        }
    }

    private enum DuplicateDeleteAction {
        case selected
        case all
    }

    private var duplicateDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteAction = nil
                }
            }
        )
    }

    private var duplicateConfirmationCount: Int {
        switch pendingDeleteAction {
        case .selected:
            selectedDuplicateIDs.count
        case .all:
            result.duplicates.count
        case nil:
            0
        }
    }

    private var duplicateConfirmationTitle: String {
        pendingDeleteAction == .all ? "Remove all duplicates?" : "Remove selected duplicates?"
    }

    private var duplicateConfirmationButtonTitle: String {
        duplicateConfirmationCount == 1 ? "Remove Duplicate" : "Remove \(duplicateConfirmationCount) Duplicates"
    }

    private var duplicateConfirmationMessage: String {
        "This removes duplicate bookmarks from the working set and keeps the paired originals. The change is written to Chrome only when you apply changes."
    }

    private func confirmOrDeleteDuplicates(_ action: DuplicateDeleteAction) {
        let count = action == .all ? result.duplicates.count : selectedDuplicateIDs.count
        guard count > 0 else { return }

        if DeletionConfirmationPolicy.shouldConfirm(skipConfirmation: skipDeleteConfirmation) {
            pendingDeleteAction = action
        } else {
            performDuplicateDelete(action)
        }
    }

    private func performPendingDuplicateDelete() {
        guard let pendingDeleteAction else { return }

        performDuplicateDelete(pendingDeleteAction)
        self.pendingDeleteAction = nil
    }

    private func performDuplicateDelete(_ action: DuplicateDeleteAction) {
        switch action {
        case .selected:
            deleteSelectedDuplicates()
        case .all:
            store.deleteAllDetectedDuplicates()
            selectedDuplicateIDs.removeAll()
        }
    }

    private func deleteSelectedDuplicates() {
        store.deleteBookmarks(withIDs: selectedDuplicateIDs)
        selectedDuplicateIDs.removeAll()
    }
}

private struct SelectionActionBar: View {
    var selectedCount: Int
    var protectedSelectedCount: Int
    @Binding var isPreviewVisible: Bool
    var protectAction: () -> Void
    var unprotectAction: () -> Void
    var deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(selectedCount == 1 ? "1 selected" : "\(selectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button(action: protectAction) {
                Label("Keep Original", systemImage: "shield")
            }
            .disabled(selectedCount == 0 || protectedSelectedCount == selectedCount)
            .help("Mark selected bookmarks so AI, export, apply, and delete leave them unchanged")

            Button(action: unprotectAction) {
                Label("Allow Changes", systemImage: "shield.slash")
            }
            .disabled(protectedSelectedCount == 0)
            .help("Allow selected bookmarks to use proposed edits again")

            Button {
                isPreviewVisible.toggle()
            } label: {
                Label(isPreviewVisible ? "Hide Preview" : "Show Preview", systemImage: "sidebar.right")
            }
            .help(isPreviewVisible ? "Collapse the bookmark preview panel" : "Show the bookmark preview panel")

            Button(role: .destructive, action: deleteAction) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedCount == 0 || protectedSelectedCount == selectedCount)
            .help("Delete selected unprotected bookmark rows from this working set")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct BookmarkPreviewPanel: View {
    var store: BookmarkLibraryStore
    var selectedBookmarks: [BookmarkItem]
    var proposedTitle: String?
    var proposedFolderPath: [String]?
    var isProtected: Bool
    var collapseAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Preview", systemImage: "sidebar.right")
                    .font(.headline)

                Spacer()

                Button(action: collapseAction) {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
                .help("Collapse preview")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.bar)

            Divider()

            content
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if selectedBookmarks.isEmpty {
            EmptyPreviewState(
                systemImage: "bookmark",
                title: "No Bookmark Selected",
                message: "Select a row in Review to inspect its details and page preview."
            )
        } else if selectedBookmarks.count > 1 {
            EmptyPreviewState(
                systemImage: "checklist",
                title: "\(selectedBookmarks.count) Bookmarks Selected",
                message: "Select a single bookmark to show a page preview."
            )
        } else if let bookmark = selectedBookmarks.first {
            SingleBookmarkPreview(
                store: store,
                bookmark: bookmark,
                proposedTitle: proposedTitle,
                proposedFolderPath: proposedFolderPath,
                isProtected: isProtected
            )
        }
    }
}

private struct EmptyPreviewState: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct SingleBookmarkPreview: View {
    var store: BookmarkLibraryStore
    var bookmark: BookmarkItem
    var proposedTitle: String?
    var proposedFolderPath: [String]?
    var isProtected: Bool

    @State private var previewState = WebPreviewState.idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if isProtected {
                    Label("Keeping original", systemImage: "shield.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Text(bookmark.title)
                    .font(.headline)
                    .lineLimit(2)

                if let proposedTitle, proposedTitle != bookmark.title {
                    Text(proposedTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Label(bookmark.folderPath.joined(separator: " / "), systemImage: "folder")
                        .lineLimit(2)

                    Label(destinationFolderText, systemImage: "arrow.turn.down.right")
                        .foregroundStyle(destinationFolderText == bookmark.folderPath.joined(separator: " / ") ? .secondary : .primary)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Destination Folder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    DestinationFolderEditor(store: store, bookmark: bookmark)
                }

                Link(destination: bookmark.url) {
                    Text(bookmark.url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }
            .padding(12)

            Divider()

            previewContent
        }
        .onChange(of: bookmark.id) { _, _ in
            previewState = .idle
        }
    }

    private var destinationFolderText: String {
        proposedFolderPath?.joined(separator: " / ") ?? bookmark.folderPath.joined(separator: " / ")
    }

    @ViewBuilder
    private var previewContent: some View {
        if bookmark.url.canShowLivePreview {
            ZStack {
                WebPreview(url: bookmark.url, state: $previewState)
                    .id(bookmark.id)

                switch previewState {
                case .idle, .loading:
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                case .loaded:
                    EmptyView()
                case .failed(let message):
                    EmptyPreviewState(
                        systemImage: "exclamationmark.triangle",
                        title: "Preview Unavailable",
                        message: message
                    )
                    .background(.regularMaterial)
                }
            }
            .overlay(alignment: .bottom) {
                Text("Live browser preview")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        } else {
            EmptyPreviewState(
                systemImage: "safari",
                title: "Preview Unavailable",
                message: "Live preview supports web bookmarks with http or https URLs."
            )
        }
    }
}

private struct FolderPathCell: View {
    var folderPath: [String]

    var body: some View {
        Text(folderPath.joined(separator: " / "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(folderPath.joined(separator: " / "))
    }
}

private struct EnrichmentStatusIcon: View {
    var status: BookmarkEnrichmentStatus

    var body: some View {
        Group {
            switch status {
            case .notEnriched:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .help("Not enriched yet")
            case .enriched:
                Image(systemName: "sparkles")
                    .foregroundStyle(.green)
                    .help("Enriched in this processing run")
            case .cached:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .help("Enrichment restored from cache")
            case .edited:
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                    .help("Edited manually")
            case .protected:
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                    .help("Kept unchanged")
            }
        }
        .imageScale(.small)
        .frame(width: 22)
    }
}

private struct ProtectionToggle: View {
    var isProtected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isProtected ? "shield.fill" : "shield")
                .foregroundStyle(isProtected ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
                .imageScale(.small)
                .frame(width: 22)
        }
        .buttonStyle(.borderless)
        .help(isProtected ? "Allow this bookmark to be changed" : "Keep this bookmark unchanged")
    }
}

private struct EditableProposedTitleCell: View {
    var store: BookmarkLibraryStore
    var bookmark: BookmarkItem

    var body: some View {
        TextField("Proposed title", text: Binding(
            get: { store.proposedTitle(for: bookmark) },
            set: { store.setProposedTitle($0, for: bookmark) }
        ))
        .textFieldStyle(.plain)
        .disabled(store.isBookmarkProtected(bookmark))
        .foregroundStyle(store.isBookmarkProtected(bookmark) ? .secondary : .primary)
        .lineLimit(1)
        .help(store.isBookmarkProtected(bookmark) ? "This bookmark is marked to keep its original title" : "Edit the proposed title in place")
    }
}

private struct EditableDestinationFolderCell: View {
    var store: BookmarkLibraryStore
    var bookmark: BookmarkItem

    var body: some View {
        DestinationFolderEditor(store: store, bookmark: bookmark)
    }
}

private struct DestinationFolderEditor: View {
    var store: BookmarkLibraryStore
    var bookmark: BookmarkItem

    var body: some View {
        TextField("Folder / Subfolder", text: Binding(
            get: { store.proposedFolderText(for: bookmark) },
            set: { store.setProposedFolderText($0, for: bookmark) }
        ))
        .textFieldStyle(.plain)
        .foregroundStyle(store.proposedFolderPath(for: bookmark) == bookmark.folderPath ? .secondary : .primary)
        .disabled(store.isBookmarkProtected(bookmark))
        .lineLimit(1)
        .truncationMode(.middle)
        .help(store.isBookmarkProtected(bookmark) ? "This bookmark is marked to keep its original folder" : "Edit the destination folder path using / between folders")
    }
}

private enum WebPreviewState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

private struct WebPreview: NSViewRepresentable {
    var url: URL
    @Binding var state: WebPreviewState

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.state = $state
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        state = .loading
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: $state)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var state: Binding<WebPreviewState>
        var currentURL: URL?

        init(state: Binding<WebPreviewState>) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateState(for: webView.url, to: .loaded)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateState(for: webView.url, to: .failed(previewErrorMessage(from: error)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateState(for: webView.url ?? currentURL, to: .failed(previewErrorMessage(from: error)))
        }

        private func updateState(for url: URL?, to newState: WebPreviewState) {
            guard url == currentURL else { return }
            DispatchQueue.main.async {
                self.state.wrappedValue = newState
            }
        }

        private func previewErrorMessage(from error: Error) -> String {
            let nsError = error as NSError
            guard nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled else {
                return "Preview was cancelled while loading another bookmark."
            }

            return nsError.localizedDescription
        }
    }
}

private extension URL {
    var canShowLivePreview: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private struct BookmarkURLLink: View {
    var url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Text(url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.small)
            }
        }
        .buttonStyle(.link)
        .help("Open \(url.absoluteString)")
    }
}

private struct StorageView: View {
    var store: BookmarkLibraryStore
    @AppStorage("requireChromeClosed") private var requireChromeClosed = true
    @AppStorage("createBackupBeforeWrite") private var createBackupBeforeWrite = true
    @AppStorage("preserveBookmarksBarFolders") private var preserveBookmarksBarFolders = true
    @State private var isApplying = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeaderView(title: "Storage", subtitle: "Bookmark file, backups, and write checks")

            Label(
                store.isChromeRunning ? "Chrome is running" : "Chrome is not running",
                systemImage: store.isChromeRunning ? "xmark.octagon.fill" : "checkmark.seal.fill"
            )
            .foregroundStyle(store.isChromeRunning ? .red : .green)

            if let bookmarkFile = store.selectedBookmarkFile {
                Text(bookmarkFile.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    createBackupBeforeWrite ? "A backup will be created before writing." : "Backup creation is disabled.",
                    systemImage: createBackupBeforeWrite ? "externaldrive.badge.checkmark" : "externaldrive.badge.xmark"
                )

                Label(
                    "Apply writes reviewed title changes and removed bookmarks back to the loaded Chrome Bookmarks file.",
                    systemImage: "square.and.pencil"
                )

                Label(
                    preserveBookmarksBarFolders ? "Bookmarks Bar folders and groups will be preserved." : "Empty Bookmarks Bar folders may be removed.",
                    systemImage: preserveBookmarksBarFolders ? "folder.badge.gearshape" : "folder.badge.minus"
                )

                if hasFolderMoveProposals {
                    Label(
                        "Proposed folder moves are not written yet; export keeps those proposals for review.",
                        systemImage: "folder.badge.questionmark"
                    )
                }

                Label(
                    savedStateDescription,
                    systemImage: store.savedWorkingStateUpdatedAt == nil ? "tray" : "tray.full"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    saveLocalState()
                } label: {
                    Label("Save Local State", systemImage: "tray.and.arrow.down")
                }
                .disabled(store.selectedBookmarkFile == nil || store.isBusy || isApplying)
                .help("Save current local edits, protected rows, and local deletions so they restore after reopening")

                Button {
                    discardLocalState()
                } label: {
                    Label("Forget Saved State", systemImage: "trash")
                }
                .disabled(store.selectedBookmarkFile == nil || store.savedWorkingStateUpdatedAt == nil || store.isBusy || isApplying)
                .help("Remove the saved local edit state for this Chrome Bookmarks file")

                Button {
                    store.refreshChromeStatus()
                } label: {
                    Label("Refresh Chrome Status", systemImage: "arrow.clockwise")
                }
                .disabled(store.isBusy || isApplying)

                Button {
                    applyChanges()
                } label: {
                    if isApplying {
                        Label("Applying...", systemImage: "hourglass")
                    } else {
                        Label("Apply Changes", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(!store.canApplyChanges(requireChromeClosed: requireChromeClosed) || isApplying)
                .help(applyHelpText)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            store.refreshChromeStatus()
        }
    }

    private var hasFolderMoveProposals: Bool {
        store.snapshot.bookmarks.contains { bookmark in
            !store.isBookmarkProtected(bookmark)
                && store.proposedFolderPath(for: bookmark) != bookmark.folderPath
        }
    }

    private var applyHelpText: String {
        if store.selectedBookmarkFile == nil {
            return "Load a Chrome Bookmarks file before applying changes"
        }

        if store.snapshot.bookmarks.isEmpty {
            return "There are no bookmarks loaded to apply"
        }

        if requireChromeClosed && store.isChromeRunning {
            return "Close Chrome, then refresh Chrome status"
        }

        return "Write reviewed title and deletion changes back to the Chrome Bookmarks file"
    }

    private var savedStateDescription: String {
        guard let updatedAt = store.savedWorkingStateUpdatedAt else {
            return "No saved local edit state for this bookmark file."
        }

        return "Local edit state saved \(updatedAt.formatted(date: .abbreviated, time: .shortened))."
    }

    private func saveLocalState() {
        do {
            try store.saveCurrentWorkingState()
            statusMessage = "Local edit state was saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func discardLocalState() {
        do {
            try store.discardSavedWorkingState()
            statusMessage = "Saved local edit state was removed. Current in-memory edits are unchanged."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func applyChanges() {
        guard !isApplying else { return }

        isApplying = true
        statusMessage = "Checking Chrome and writing changes..."

        Task {
            do {
                try await store.applyChanges(
                    requireChromeClosed: requireChromeClosed,
                    createBackup: createBackupBeforeWrite,
                    preserveBookmarksBarFolders: preserveBookmarksBarFolders
                )
                statusMessage = "Changes were applied to the Chrome Bookmarks file."
            } catch {
                statusMessage = error.localizedDescription
            }

            isApplying = false
        }
    }
}

private struct HeaderView: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricView: View {
    var title: String
    var value: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(value)
                    .font(.title.bold())
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
