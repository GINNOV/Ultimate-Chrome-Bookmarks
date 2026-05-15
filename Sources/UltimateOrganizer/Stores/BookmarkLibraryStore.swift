import CryptoKit
import Foundation
import Observation
import UltimateOrganizerCore

@MainActor
@Observable
final class BookmarkLibraryStore {
    enum LoadingState: Equatable {
        case idle
        case importing
        case processing
        case loaded
        case failed(String)
    }

    var bookmarkFiles: [URL] = []
    var selectedBookmarkFile: URL?
    var snapshot = BookmarkSnapshot(roots: [], bookmarks: [])
    var duplicateResult = DuplicateMergeResult(unique: [], duplicates: [])
    var proposedTitles: [String: String] = [:]
    var proposedFolderPaths: [String: [String]] = [:]
    var enrichedBookmarkIDs: Set<BookmarkItem.ID> = []
    var cachedEnrichmentBookmarkIDs: Set<BookmarkItem.ID> = []
    var manuallyEditedBookmarkIDs: Set<BookmarkItem.ID> = []
    var protectedBookmarkIDs: Set<BookmarkItem.ID> = []
    var locallyDeletedBookmarkIDs: Set<BookmarkItem.ID> = []
    var savedWorkingStateUpdatedAt: Date?
    var enrichmentSummary: BookmarkEnrichmentSummary?
    var isChromeRunning = false
    var state: LoadingState = .idle
    var importProgress = BookmarkImportProgress(processedItems: 0, totalItems: 0)
    var isBusy: Bool {
        state == .importing || state == .processing
    }

    private let locator: ChromeBookmarkLocator
    private let parser: ChromeBookmarksParser
    private let merger: DuplicateBookmarkMerger
    private let writer: ChromeBookmarksWriter
    private let processDetector: ChromeProcessDetector
    private var processingTask: Task<Void, Never>?
    private var enrichmentCache: [String: CachedBookmarkEnrichment]

    init(
        locator: ChromeBookmarkLocator = ChromeBookmarkLocator(),
        parser: ChromeBookmarksParser = ChromeBookmarksParser(),
        merger: DuplicateBookmarkMerger = DuplicateBookmarkMerger(),
        writer: ChromeBookmarksWriter = ChromeBookmarksWriter(),
        processDetector: ChromeProcessDetector = ChromeProcessDetector()
    ) {
        self.locator = locator
        self.parser = parser
        self.merger = merger
        self.writer = writer
        self.processDetector = processDetector
        self.enrichmentCache = Self.loadEnrichmentCache()
    }

    func refresh() {
        guard !isBusy else { return }

        state = .importing
        importProgress = BookmarkImportProgress(
            processedItems: 0,
            totalItems: 0,
            currentItemTitle: "Checking Chrome and bookmark files"
        )

        Task {
            do {
                let startedAt = Date()
                let selectedFile = selectedBookmarkFile
                let preflight = await runPreflight()

                isChromeRunning = preflight.isChromeRunning
                bookmarkFiles = preflight.bookmarkFiles

                guard let file = selectedFile ?? preflight.bookmarkFiles.first else {
                    snapshot = BookmarkSnapshot(roots: [], bookmarks: [])
                    duplicateResult = DuplicateMergeResult(unique: [], duplicates: [])
                    importProgress = BookmarkImportProgress(processedItems: 0, totalItems: 0)
                    state = .failed("No Chrome bookmark file was found.")
                    return
                }

                selectedBookmarkFile = file
                let result = try await importBookmarks(from: file)
                await keepProgressVisibleIfNeeded(startedAt: startedAt)
                restoreWorkingState(from: result, for: file)
                importProgress = BookmarkImportProgress(
                    processedItems: snapshot.bookmarks.count,
                    totalItems: snapshot.bookmarks.count
                )
                state = .loaded
            } catch {
                snapshot = BookmarkSnapshot(roots: [], bookmarks: [])
                duplicateResult = DuplicateMergeResult(unique: [], duplicates: [])
                state = .failed(error.localizedDescription)
            }
        }
    }

    func importBookmarksFile(_ file: URL) {
        guard !isBusy else { return }

        selectedBookmarkFile = file
        state = .importing
        importProgress = BookmarkImportProgress(
            processedItems: 0,
            totalItems: 0,
            currentItemTitle: "Preparing import"
        )

        Task {
            do {
                let startedAt = Date()
                let result = try await importBookmarks(from: file)
                await keepProgressVisibleIfNeeded(startedAt: startedAt)
                restoreWorkingState(from: result, for: file)
                importProgress = BookmarkImportProgress(
                    processedItems: snapshot.bookmarks.count,
                    totalItems: snapshot.bookmarks.count
                )
                state = .loaded
            } catch {
                snapshot = BookmarkSnapshot(roots: [], bookmarks: [])
                duplicateResult = DuplicateMergeResult(unique: [], duplicates: [])
                state = .failed(error.localizedDescription)
            }
        }
    }

    func startProcessing() {
        guard state != .processing, !snapshot.bookmarks.isEmpty else { return }

        processingTask?.cancel()
        enrichmentSummary = nil
        state = .processing
        importProgress = BookmarkImportProgress(
            processedItems: 0,
            totalItems: snapshot.bookmarks.count,
            currentItemTitle: "Preparing AI enrichment"
        )

        let bookmarks = snapshot.bookmarks
        processingTask = Task { [bookmarks] in
            let client = makeOllamaClient()
            let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.1"
            let contextWindow = UserDefaults.standard.integer(forKey: "localAIContextWindow")
            var freshCount = 0
            var cachedCount = 0
            var failedCount = 0
            let shouldUseCache = Self.isEnrichmentCacheEnabled()

            for (index, bookmark) in bookmarks.enumerated() {
                guard !Task.isCancelled else {
                    importProgress = BookmarkImportProgress(
                        processedItems: index,
                        totalItems: bookmarks.count,
                        currentItemTitle: "Processing stopped"
                    )
                    state = .loaded
                    return
                }

                importProgress = BookmarkImportProgress(
                    processedItems: index + 1,
                    totalItems: bookmarks.count,
                    currentItemTitle: "Enriching \(bookmark.title)"
                )

                if protectedBookmarkIDs.contains(bookmark.id) {
                    proposedTitles[bookmark.id] = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    proposedFolderPaths[bookmark.id] = bookmark.folderPath
                    enrichedBookmarkIDs.remove(bookmark.id)
                    cachedEnrichmentBookmarkIDs.remove(bookmark.id)
                    manuallyEditedBookmarkIDs.remove(bookmark.id)
                    continue
                }

                if manuallyEditedBookmarkIDs.contains(bookmark.id) {
                    enrichedBookmarkIDs.insert(bookmark.id)
                    cachedEnrichmentBookmarkIDs.remove(bookmark.id)
                    continue
                }

                if shouldUseCache, let cached = enrichmentCache[cacheKey(for: bookmark)] {
                    proposedTitles[bookmark.id] = cached.proposedTitle
                    proposedFolderPaths[bookmark.id] = cached.proposedFolderPath
                    enrichedBookmarkIDs.insert(bookmark.id)
                    cachedEnrichmentBookmarkIDs.insert(bookmark.id)
                    manuallyEditedBookmarkIDs.remove(bookmark.id)
                    cachedCount += 1
                    continue
                }

                let prompt = """
                Enrich this browser bookmark for a clean bookmark organizer.
                Return only compact JSON with this exact shape:
                {"title":"Concise title","folderPath":["Folder","Subfolder"]}

                Use folderPath for a clean proposed folder hierarchy. Keep it short and practical.

                Current title: \(bookmark.title)
                Current folder: \(bookmark.folderPath.joined(separator: " / "))
                URL: \(bookmark.url.absoluteString)
                """

                if let response = try? await client.generate(
                    model: model,
                    prompt: prompt,
                    contextWindow: contextWindow > 0 ? contextWindow : nil
                ) {
                    let enrichment = parsedEnrichment(from: response, fallbackBookmark: bookmark)
                    proposedTitles[bookmark.id] = enrichment.title
                    proposedFolderPaths[bookmark.id] = enrichment.folderPath
                    enrichedBookmarkIDs.insert(bookmark.id)
                    cachedEnrichmentBookmarkIDs.remove(bookmark.id)
                    manuallyEditedBookmarkIDs.remove(bookmark.id)
                    cache(enrichment, for: bookmark)
                    freshCount += 1
                } else {
                    proposedTitles[bookmark.id] = cleanedTitle(from: bookmark.title, fallback: bookmark.title)
                    proposedFolderPaths[bookmark.id] = bookmark.folderPath
                    enrichedBookmarkIDs.remove(bookmark.id)
                    cachedEnrichmentBookmarkIDs.remove(bookmark.id)
                    manuallyEditedBookmarkIDs.remove(bookmark.id)
                    failedCount += 1
                }
            }

            importProgress = BookmarkImportProgress(
                processedItems: bookmarks.count,
                totalItems: bookmarks.count,
                currentItemTitle: "AI enrichment complete"
            )
            enrichmentSummary = makeEnrichmentSummary(
                bookmarks: bookmarks,
                freshCount: freshCount,
                cachedCount: cachedCount,
                failedCount: failedCount
            )
            try? saveCurrentWorkingState()
            state = .loaded
        }
    }

    func proposedTitle(for bookmark: BookmarkItem) -> String {
        if protectedBookmarkIDs.contains(bookmark.id) {
            return bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return proposedTitles[bookmark.id] ?? bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func proposedFolderPath(for bookmark: BookmarkItem) -> [String] {
        if protectedBookmarkIDs.contains(bookmark.id) {
            return bookmark.folderPath
        }

        return proposedFolderPaths[bookmark.id] ?? bookmark.folderPath
    }

    func setProposedTitle(_ title: String, for bookmark: BookmarkItem) {
        guard !protectedBookmarkIDs.contains(bookmark.id) else { return }

        let cleanedTitle = cleanedTitle(from: title, fallback: bookmark.title)
        proposedTitles[bookmark.id] = cleanedTitle
        markManuallyEdited(bookmark.id)
        try? saveCurrentWorkingState()
    }

    func proposedFolderText(for bookmark: BookmarkItem) -> String {
        proposedFolderPath(for: bookmark).joined(separator: " / ")
    }

    func setProposedFolderText(_ folderText: String, for bookmark: BookmarkItem) {
        guard !protectedBookmarkIDs.contains(bookmark.id) else { return }

        proposedFolderPaths[bookmark.id] = sanitizedFolderPath(
            folderText.components(separatedBy: "/"),
            fallback: bookmark.folderPath
        )
        markManuallyEdited(bookmark.id)
        try? saveCurrentWorkingState()
    }

    func enrichmentStatus(for bookmark: BookmarkItem) -> BookmarkEnrichmentStatus {
        if protectedBookmarkIDs.contains(bookmark.id) { return .protected }
        if manuallyEditedBookmarkIDs.contains(bookmark.id) { return .edited }
        guard enrichedBookmarkIDs.contains(bookmark.id) else { return .notEnriched }
        return cachedEnrichmentBookmarkIDs.contains(bookmark.id) ? .cached : .enriched
    }

    func bookmarks(_ bookmarks: [BookmarkItem], matching searchText: String) -> [BookmarkItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return bookmarks }

        return bookmarks.filter { bookmark in
            searchableFields(for: bookmark).contains { field in
                field.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func isBookmarkProtected(_ bookmark: BookmarkItem) -> Bool {
        protectedBookmarkIDs.contains(bookmark.id)
    }

    func setBookmarkProtection(_ isProtected: Bool, for ids: Set<BookmarkItem.ID>) {
        guard !ids.isEmpty, !isBusy else { return }

        if isProtected {
            protectedBookmarkIDs.formUnion(ids)
        } else {
            protectedBookmarkIDs.subtract(ids)
        }

        try? saveCurrentWorkingState()
    }

    func toggleBookmarkProtection(for bookmark: BookmarkItem) {
        setBookmarkProtection(!protectedBookmarkIDs.contains(bookmark.id), for: [bookmark.id])
    }

    func deleteBookmarks(withIDs ids: Set<BookmarkItem.ID>) {
        guard !ids.isEmpty, !isBusy else { return }

        let removableIDs = ids.subtracting(protectedBookmarkIDs)
        guard !removableIDs.isEmpty else { return }

        snapshot = snapshot.removingBookmarks(withIDs: removableIDs)
        duplicateResult = merger.merge(snapshot.bookmarks)
        locallyDeletedBookmarkIDs.formUnion(removableIDs)

        for id in removableIDs {
            proposedTitles[id] = nil
            proposedFolderPaths[id] = nil
            enrichedBookmarkIDs.remove(id)
            cachedEnrichmentBookmarkIDs.remove(id)
            manuallyEditedBookmarkIDs.remove(id)
            protectedBookmarkIDs.remove(id)
        }

        try? saveCurrentWorkingState()
    }

    func deleteAllDetectedDuplicates() {
        deleteBookmarks(withIDs: Set(duplicateResult.duplicates.map(\.duplicate.id)))
    }

    func clearEnrichmentCache() {
        enrichmentCache = [:]

        for id in cachedEnrichmentBookmarkIDs {
            proposedTitles[id] = nil
            proposedFolderPaths[id] = nil
            enrichedBookmarkIDs.remove(id)
            manuallyEditedBookmarkIDs.remove(id)
        }

        cachedEnrichmentBookmarkIDs = []
        Self.deleteEnrichmentCache()
    }

    func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil

        if state == .processing {
            importProgress = BookmarkImportProgress(
                processedItems: importProgress.processedItems,
                totalItems: importProgress.totalItems,
                currentItemTitle: "Processing stopped"
            )
            state = .loaded
        }
    }

    func refreshChromeStatus() {
        Task {
            let isRunning = await detectChromeRunning()
            isChromeRunning = isRunning
        }
    }

    func canApplyChanges(requireChromeClosed: Bool) -> Bool {
        selectedBookmarkFile != nil
            && !snapshot.bookmarks.isEmpty
            && !isBusy
            && (!requireChromeClosed || !isChromeRunning)
    }

    func applyChanges(
        requireChromeClosed: Bool,
        createBackup: Bool,
        preserveBookmarksBarFolders: Bool
    ) async throws {
        guard !isBusy else { throw BookmarkApplyError.busy }
        guard let file = selectedBookmarkFile else { throw BookmarkApplyError.noBookmarkFile }

        let chromeRunning = await detectChromeRunning()
        isChromeRunning = chromeRunning

        if requireChromeClosed && chromeRunning {
            throw BookmarkApplyError.chromeIsRunning
        }

        let data = try Data(contentsOf: file)
        if createBackup {
            try FileManager.default.copyItem(at: file, to: backupURL(for: file))
        }

        let proposedTitlesByID = Dictionary(
            uniqueKeysWithValues: snapshot.bookmarks.map { bookmark in
                let title = protectedBookmarkIDs.contains(bookmark.id)
                    ? bookmark.title
                    : proposedTitle(for: bookmark)
                return (bookmark.id, title)
            }
        )
        let updatedData = try writer.applyChanges(
            to: data,
            keepingBookmarkIDs: Set(snapshot.bookmarks.map(\.id)),
            proposedTitles: proposedTitlesByID,
            preserveBookmarksBarFolders: preserveBookmarksBarFolders
        )

        try updatedData.write(to: file, options: .atomic)
        let result = try await importBookmarks(from: file)
        restoreWorkingState(from: result, for: file)
        try? saveCurrentWorkingState()
    }

    func checkLocalAIService() async -> LocalAIServiceStatus {
        let client = makeOllamaClient()
        let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.1"
        return await client.checkService(configuredModel: model)
    }

    func exportBookmarks(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let export = BookmarkExport(
            sourcePath: selectedBookmarkFile?.path,
            exportedAt: Date(),
            bookmarks: snapshot.bookmarks.map { bookmark in
                ExportedBookmark(
                    bookmark: bookmark,
                    proposedTitle: proposedTitle(for: bookmark),
                    proposedFolderPath: proposedFolderPath(for: bookmark),
                    isProtected: protectedBookmarkIDs.contains(bookmark.id)
                )
            }
        )
        let data = try encoder.encode(export)
        try data.write(to: file, options: .atomic)
    }

    func saveCurrentWorkingState() throws {
        guard let file = selectedBookmarkFile else { throw BookmarkWorkingStateError.noBookmarkFile }

        let state = SavedBookmarkWorkingState(
            sourcePath: file.path,
            updatedAt: Date(),
            proposedTitles: proposedTitles,
            proposedFolderPaths: proposedFolderPaths,
            enrichedBookmarkIDs: Array(enrichedBookmarkIDs),
            cachedEnrichmentBookmarkIDs: Array(cachedEnrichmentBookmarkIDs),
            manuallyEditedBookmarkIDs: Array(manuallyEditedBookmarkIDs),
            protectedBookmarkIDs: Array(protectedBookmarkIDs),
            locallyDeletedBookmarkIDs: Array(locallyDeletedBookmarkIDs)
        )

        let url = workingStateURL(for: file)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
        savedWorkingStateUpdatedAt = state.updatedAt
    }

    func discardSavedWorkingState() throws {
        guard let file = selectedBookmarkFile else { throw BookmarkWorkingStateError.noBookmarkFile }

        try? FileManager.default.removeItem(at: workingStateURL(for: file))
        savedWorkingStateUpdatedAt = nil
    }

    private func restoreWorkingState(from result: ImportResult, for file: URL) {
        snapshot = result.snapshot
        applyCachedEnrichments(to: result.snapshot.bookmarks)
        locallyDeletedBookmarkIDs = []
        savedWorkingStateUpdatedAt = nil

        if let savedState = loadWorkingState(for: file) {
            apply(savedState)
        }

        duplicateResult = merger.merge(snapshot.bookmarks)
    }

    private func apply(_ savedState: SavedBookmarkWorkingState) {
        let existingIDs = Set(snapshot.bookmarks.map(\.id))
        let deletedIDs = Set(savedState.locallyDeletedBookmarkIDs).intersection(existingIDs)

        if !deletedIDs.isEmpty {
            snapshot = snapshot.removingBookmarks(withIDs: deletedIDs)
        }

        let activeIDs = Set(snapshot.bookmarks.map(\.id))

        proposedTitles.merge(savedState.proposedTitles.filter { activeIDs.contains($0.key) }) { _, saved in saved }
        proposedFolderPaths.merge(savedState.proposedFolderPaths.filter { activeIDs.contains($0.key) }) { _, saved in saved }
        enrichedBookmarkIDs.formUnion(Set(savedState.enrichedBookmarkIDs).intersection(activeIDs))
        cachedEnrichmentBookmarkIDs.formUnion(Set(savedState.cachedEnrichmentBookmarkIDs).intersection(activeIDs))
        manuallyEditedBookmarkIDs.formUnion(Set(savedState.manuallyEditedBookmarkIDs).intersection(activeIDs))
        protectedBookmarkIDs.formUnion(Set(savedState.protectedBookmarkIDs).intersection(activeIDs))
        locallyDeletedBookmarkIDs = deletedIDs
        savedWorkingStateUpdatedAt = savedState.updatedAt
    }

    private func loadWorkingState(for file: URL) -> SavedBookmarkWorkingState? {
        let url = workingStateURL(for: file)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SavedBookmarkWorkingState.self, from: data),
              state.sourcePath == file.path
        else {
            return nil
        }

        return state
    }

    private func workingStateURL(for file: URL) -> URL {
        Self.workingStateDirectory()
            .appendingPathComponent(workingStateKey(for: file), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func workingStateKey(for file: URL) -> String {
        let digest = SHA256.hash(data: Data(file.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func searchableFields(for bookmark: BookmarkItem) -> [String] {
        let currentFolder = bookmark.folderPath.joined(separator: " / ")
        let proposedFolder = proposedFolderPath(for: bookmark).joined(separator: " / ")

        return [
            bookmark.id,
            bookmark.title,
            proposedTitle(for: bookmark),
            bookmark.url.absoluteString,
            bookmark.url.host ?? "",
            bookmark.url.path,
            bookmark.url.query ?? "",
            currentFolder,
            proposedFolder,
            bookmark.folderPath.joined(separator: " "),
            proposedFolderPath(for: bookmark).joined(separator: " "),
            isBookmarkProtected(bookmark) ? "keep original protected" : "allow changes",
            searchText(for: enrichmentStatus(for: bookmark))
        ]
    }

    private func searchText(for status: BookmarkEnrichmentStatus) -> String {
        switch status {
        case .notEnriched:
            return "not enriched"
        case .enriched:
            return "enriched"
        case .cached:
            return "cached"
        case .edited:
            return "edited manually"
        case .protected:
            return "protected keep original"
        }
    }

    private func makeOllamaClient() -> OllamaClient {
        let rawEndpoint = UserDefaults.standard.string(forKey: "ollamaEndpoint") ?? "http://localhost:11434"
        let timeout = UserDefaults.standard.double(forKey: "ollamaTimeout")
        let baseURL = URL(string: rawEndpoint) ?? URL(string: "http://localhost:11434")!
        return OllamaClient(baseURL: baseURL, timeoutInterval: timeout > 0 ? timeout : 60)
    }

    private func cleanedTitle(from response: String, fallback: String) -> String {
        let cleaned = response
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            ?? ""

        return cleaned.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    private func parsedEnrichment(from response: String, fallbackBookmark bookmark: BookmarkItem) -> BookmarkEnrichment {
        let fallback = BookmarkEnrichment(
            title: cleanedTitle(from: response, fallback: bookmark.title),
            folderPath: bookmark.folderPath
        )

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            jsonObjectSubstring(in: trimmed)
        ].compactMap(\.self)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(AIEnrichmentResponse.self, from: data)
            else {
                continue
            }

            let title = cleanedTitle(from: decoded.title ?? "", fallback: bookmark.title)
            let folderPath = sanitizedFolderPath(decoded.folderPath, fallback: bookmark.folderPath)
            return BookmarkEnrichment(title: title, folderPath: folderPath)
        }

        return fallback
    }

    private func jsonObjectSubstring(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }

        return String(text[start...end])
    }

    private func sanitizedFolderPath(_ folderPath: [String]?, fallback: [String]) -> [String] {
        let cleaned = (folderPath ?? [])
            .map { component in
                component.trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))
                )
            }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? fallback : cleaned
    }

    private func applyCachedEnrichments(to bookmarks: [BookmarkItem]) {
        proposedTitles = [:]
        proposedFolderPaths = [:]
        enrichedBookmarkIDs = []
        cachedEnrichmentBookmarkIDs = []
        manuallyEditedBookmarkIDs = []
        protectedBookmarkIDs = []

        guard Self.isEnrichmentCacheEnabled() else { return }

        for bookmark in bookmarks {
            guard let cached = enrichmentCache[cacheKey(for: bookmark)] else { continue }

            proposedTitles[bookmark.id] = cached.proposedTitle
            proposedFolderPaths[bookmark.id] = cached.proposedFolderPath
            enrichedBookmarkIDs.insert(bookmark.id)
            cachedEnrichmentBookmarkIDs.insert(bookmark.id)
        }
    }

    private func markManuallyEdited(_ id: BookmarkItem.ID) {
        enrichedBookmarkIDs.insert(id)
        cachedEnrichmentBookmarkIDs.remove(id)
        manuallyEditedBookmarkIDs.insert(id)
    }

    private func cache(_ enrichment: BookmarkEnrichment, for bookmark: BookmarkItem) {
        guard Self.isEnrichmentCacheEnabled() else { return }

        let key = cacheKey(for: bookmark)
        enrichmentCache[key] = CachedBookmarkEnrichment(
            key: key,
            originalTitle: bookmark.title,
            url: bookmark.url.absoluteString,
            originalFolderPath: bookmark.folderPath,
            proposedTitle: enrichment.title,
            proposedFolderPath: enrichment.folderPath,
            enrichedAt: Date()
        )
        Self.saveEnrichmentCache(enrichmentCache)
    }

    private func cacheKey(for bookmark: BookmarkItem) -> String {
        let rawKey = [
            bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines),
            bookmark.url.absoluteString,
            bookmark.folderPath.joined(separator: "\u{1F}")
        ].joined(separator: "\u{1E}")

        let digest = SHA256.hash(data: Data(rawKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeEnrichmentSummary(
        bookmarks: [BookmarkItem],
        freshCount: Int,
        cachedCount: Int,
        failedCount: Int
    ) -> BookmarkEnrichmentSummary {
        var changedTitleCount = 0
        var changedFolderCount = 0
        var unchangedCount = 0
        var folderCounts: [String: Int] = [:]

        for bookmark in bookmarks where enrichedBookmarkIDs.contains(bookmark.id) && !protectedBookmarkIDs.contains(bookmark.id) {
            let proposedTitle = proposedTitle(for: bookmark)
            let proposedFolderPath = proposedFolderPath(for: bookmark)
            let titleChanged = proposedTitle != bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let folderChanged = proposedFolderPath != bookmark.folderPath

            if titleChanged {
                changedTitleCount += 1
            }

            if folderChanged {
                changedFolderCount += 1
            }

            if !titleChanged && !folderChanged {
                unchangedCount += 1
            }

            let folderName = proposedFolderPath.isEmpty ? "Bookmarks Bar" : proposedFolderPath.joined(separator: " / ")
            folderCounts[folderName, default: 0] += 1
        }

        let topFolders = folderCounts
            .map { BookmarkFolderInsight(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
            .prefix(5)

        let enrichedCount = freshCount + cachedCount
        var insights: [String] = []

        if cachedCount > 0 {
            insights.append("\(cachedCount) unchanged bookmark inputs reused cached enrichment and skipped local AI.")
        }

        if changedFolderCount > 0 {
            insights.append("\(changedFolderCount) bookmarks have proposed folder moves.")
        }

        if changedTitleCount > 0 {
            insights.append("\(changedTitleCount) titles were simplified or clarified.")
        }

        if unchangedCount > 0 {
            insights.append("\(unchangedCount) enriched bookmarks are already aligned with the proposed structure.")
        }

        if failedCount > 0 {
            insights.append("\(failedCount) bookmarks could not be enriched and kept their current title and folder.")
        }

        if duplicateResult.duplicates.count > 0 {
            insights.append("\(duplicateResult.duplicates.count) duplicate candidates remain available in Duplicate Cleanup.")
        }

        if insights.isEmpty {
            insights.append("No changes were proposed for this run.")
        }

        return BookmarkEnrichmentSummary(
            totalBookmarks: bookmarks.count,
            enrichedCount: enrichedCount,
            freshEnrichmentCount: freshCount,
            cachedEnrichmentCount: cachedCount,
            failedCount: failedCount,
            changedTitleCount: changedTitleCount,
            changedFolderCount: changedFolderCount,
            unchangedCount: unchangedCount,
            duplicateCount: duplicateResult.duplicates.count,
            topFolders: Array(topFolders),
            insights: insights
        )
    }

    private static func loadEnrichmentCache() -> [String: CachedBookmarkEnrichment] {
        guard isEnrichmentCacheEnabled() else { return [:] }

        let url = enrichmentCacheURL()
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: CachedBookmarkEnrichment].self, from: data)
        else {
            return [:]
        }

        return cache
    }

    private static func saveEnrichmentCache(_ cache: [String: CachedBookmarkEnrichment]) {
        guard isEnrichmentCacheEnabled() else { return }

        let url = enrichmentCacheURL()

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache persistence is an optimization; processing should still continue if it fails.
        }
    }

    private static func enrichmentCacheURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Ultimate Organizer", isDirectory: true)
            .appendingPathComponent("enrichment-cache.json")
    }

    private static func workingStateDirectory() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Ultimate Organizer", isDirectory: true)
            .appendingPathComponent("working-states", isDirectory: true)
    }

    private static func deleteEnrichmentCache() {
        try? FileManager.default.removeItem(at: enrichmentCacheURL())
    }

    private static func isEnrichmentCacheEnabled() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "useEnrichmentCache") != nil else { return true }
        return defaults.bool(forKey: "useEnrichmentCache")
    }

    private func keepProgressVisibleIfNeeded(startedAt: Date) async {
        let minimumDuration: TimeInterval = 0.35
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed < minimumDuration else { return }

        let remainingNanoseconds = UInt64((minimumDuration - elapsed) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: remainingNanoseconds)
    }

    private func runPreflight() async -> ImportPreflight {
        let locator = locator
        let processDetector = processDetector

        return await Task.detached {
            ImportPreflight(
                isChromeRunning: processDetector.isChromeRunning(),
                bookmarkFiles: locator.discoverExistingBookmarkFiles()
            )
        }.value
    }

    private func detectChromeRunning() async -> Bool {
        let processDetector = processDetector
        return await Task.detached {
            processDetector.isChromeRunning()
        }.value
    }

    private func backupURL(for file: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return file.deletingLastPathComponent()
            .appendingPathComponent("\(file.lastPathComponent).ultimate-organizer-\(timestamp).backup")
    }

    private func importBookmarks(from file: URL) async throws -> ImportResult {
        let parser = parser
        let merger = merger

        return try await Task.detached {
            await MainActor.run {
                self.importProgress = BookmarkImportProgress(
                    processedItems: 0,
                    totalItems: 0,
                    currentItemTitle: "Reading bookmark file"
                )
            }

            let data = try Data(contentsOf: file)

            await MainActor.run {
                self.importProgress = BookmarkImportProgress(
                    processedItems: 0,
                    totalItems: 0,
                    currentItemTitle: "Decoding bookmark JSON"
                )
            }

            var lastReportedItemCount = 0

            let snapshot = try parser.parse(data) { progress in
                let reportInterval = max(1, progress.totalItems / 200)
                let shouldReport = progress.processedItems == 0
                    || progress.processedItems == progress.totalItems
                    || progress.processedItems - lastReportedItemCount >= reportInterval

                guard shouldReport else { return }
                lastReportedItemCount = progress.processedItems

                Task { @MainActor in
                    self.importProgress = progress
                }
            }

            await MainActor.run {
                self.importProgress = BookmarkImportProgress(
                    processedItems: snapshot.bookmarks.count,
                    totalItems: snapshot.bookmarks.count,
                    currentItemTitle: "Finding duplicates"
                )
            }

            let duplicates = merger.merge(snapshot.bookmarks)
            return ImportResult(snapshot: snapshot, duplicates: duplicates)
        }.value
    }
}

private struct ImportResult: Sendable {
    var snapshot: BookmarkSnapshot
    var duplicates: DuplicateMergeResult
}

private struct ImportPreflight: Sendable {
    var isChromeRunning: Bool
    var bookmarkFiles: [URL]
}

enum BookmarkApplyError: LocalizedError {
    case busy
    case noBookmarkFile
    case chromeIsRunning

    var errorDescription: String? {
        switch self {
        case .busy:
            return "The bookmark library is busy. Wait for the current operation to finish."
        case .noBookmarkFile:
            return "No Chrome Bookmarks file is loaded."
        case .chromeIsRunning:
            return "Chrome is still running. Close Chrome before applying changes."
        }
    }
}

enum BookmarkWorkingStateError: LocalizedError {
    case noBookmarkFile

    var errorDescription: String? {
        switch self {
        case .noBookmarkFile:
            return "No Chrome Bookmarks file is loaded."
        }
    }
}

private struct BookmarkEnrichment: Sendable {
    var title: String
    var folderPath: [String]
}

enum BookmarkEnrichmentStatus: Equatable {
    case notEnriched
    case enriched
    case cached
    case edited
    case protected
}

struct BookmarkEnrichmentSummary: Identifiable, Equatable {
    var id = UUID()
    var totalBookmarks: Int
    var enrichedCount: Int
    var freshEnrichmentCount: Int
    var cachedEnrichmentCount: Int
    var failedCount: Int
    var changedTitleCount: Int
    var changedFolderCount: Int
    var unchangedCount: Int
    var duplicateCount: Int
    var topFolders: [BookmarkFolderInsight]
    var insights: [String]
}

struct BookmarkFolderInsight: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var count: Int
}

private struct CachedBookmarkEnrichment: Codable, Sendable {
    var key: String
    var originalTitle: String
    var url: String
    var originalFolderPath: [String]
    var proposedTitle: String
    var proposedFolderPath: [String]
    var enrichedAt: Date
}

private struct AIEnrichmentResponse: Decodable {
    var title: String?
    var folderPath: [String]?
}

private struct SavedBookmarkWorkingState: Codable, Sendable {
    var sourcePath: String
    var updatedAt: Date
    var proposedTitles: [String: String]
    var proposedFolderPaths: [String: [String]]
    var enrichedBookmarkIDs: [String]
    var cachedEnrichmentBookmarkIDs: [String]
    var manuallyEditedBookmarkIDs: [String]
    var protectedBookmarkIDs: [String]
    var locallyDeletedBookmarkIDs: [String]
}

extension BookmarkSnapshot: @unchecked Sendable {}
extension BookmarkFolder: @unchecked Sendable {}
extension BookmarkItem: @unchecked Sendable {}
extension DuplicateMergeResult: @unchecked Sendable {}
extension DuplicateBookmark: @unchecked Sendable {}

private struct BookmarkExport: Encodable {
    var sourcePath: String?
    var exportedAt: Date
    var bookmarks: [ExportedBookmark]
}

private struct ExportedBookmark: Encodable {
    var id: String
    var originalTitle: String
    var proposedTitle: String
    var url: String
    var originalFolderPath: [String]
    var proposedFolderPath: [String]
    var isProtected: Bool

    init(bookmark: BookmarkItem, proposedTitle: String, proposedFolderPath: [String], isProtected: Bool) {
        id = bookmark.id
        originalTitle = bookmark.title
        self.proposedTitle = proposedTitle
        url = bookmark.url.absoluteString
        originalFolderPath = bookmark.folderPath
        self.proposedFolderPath = proposedFolderPath
        self.isProtected = isProtected
    }
}
