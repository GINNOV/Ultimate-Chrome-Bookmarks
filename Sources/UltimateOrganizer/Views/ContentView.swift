import AppKit
import SwiftUI
import UltimateOrganizerCore

struct ContentView: View {
    @State private var store = BookmarkLibraryStore()
    @State private var isShowingSettings = false
    @State private var isShowingAbout = false
    @State private var isShowingAIServicePreflight = false
    @State private var aiServiceStatus: LocalAIServiceStatus?
    @State private var isCheckingAIService = false
    @State private var isShowingOnboarding = false
    @AppStorage("showOnboardingWizard") private var showOnboardingWizard = true
    @AppStorage("useEnrichmentCache") private var useEnrichmentCache = true
    @SceneStorage("selectedSidebarItem") private var selectedSidebarItem = SidebarItem.overview.rawValue

    var body: some View {
        VStack(spacing: 0) {
            if store.state == .importing || store.state == .processing {
                ImportProgressBar(progress: store.importProgress)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            NavigationSplitView {
                SidebarView(selection: $selectedSidebarItem, store: store)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                DetailView(selection: SidebarItem(rawValue: selectedSidebarItem) ?? .overview, store: store)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        importBookmarks()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isBusy)
                    .help("Import a Chrome Bookmarks file")

                    Button {
                        showAIServicePreflight()
                    } label: {
                        Label("Process", systemImage: "wand.and.sparkles")
                    }
                    .disabled(store.snapshot.bookmarks.isEmpty || store.isBusy)
                    .help("Run local AI enrichment on imported bookmarks")

                    Button {
                        store.stopProcessing()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(store.state != .processing)
                    .help("Stop the active AI processing run")

                    Button {
                        exportBookmarks()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.snapshot.bookmarks.isEmpty || store.isBusy)
                    .help("Export the current bookmark review as JSON")

                    Button {
                        selectedSidebarItem = SidebarItem.review.rawValue
                    } label: {
                        Label("Review", systemImage: "square.split.2x1")
                    }
                    .disabled(store.snapshot.bookmarks.isEmpty || store.isBusy)
                    .help("Show the current and proposed bookmark names")

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open settings")

                    Button {
                        isShowingAbout = true
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .help("Show app version and build information")
                }
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            store.refresh()
            isShowingOnboarding = showOnboardingWizard
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadBookmarksRequested)) { _ in
            store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAboutRequested)) { _ in
            isShowingAbout = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .enrichBookmarksRequested)) { _ in
            guard !store.snapshot.bookmarks.isEmpty, !store.isBusy else { return }
            showAIServicePreflight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enrichmentCacheDisabled)) { _ in
            store.clearEnrichmentCache()
        }
        .onChange(of: useEnrichmentCache) { _, newValue in
            if !newValue {
                store.clearEnrichmentCache()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsModalView()
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutView()
        }
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingWizardView(showOnboardingWizard: $showOnboardingWizard)
        }
        .sheet(isPresented: $isShowingAIServicePreflight) {
            AIServicePreflightView(
                status: aiServiceStatus,
                isChecking: isCheckingAIService,
                retryAction: checkAIService,
                cancelAction: { isShowingAIServicePreflight = false },
                startAction: {
                    isShowingAIServicePreflight = false
                    aiServiceStatus = nil
                    isCheckingAIService = false
                    selectedSidebarItem = SidebarItem.review.rawValue
                    store.startProcessing()
                }
            )
        }
        .sheet(isPresented: enrichmentSummaryBinding) {
            if let summary = store.enrichmentSummary {
                EnrichmentSummaryView(
                    summary: summary,
                    closeAction: { store.enrichmentSummary = nil },
                    reviewAction: {
                        store.enrichmentSummary = nil
                        selectedSidebarItem = SidebarItem.review.rawValue
                    }
                )
            }
        }
    }

    private var enrichmentSummaryBinding: Binding<Bool> {
        Binding(
            get: { store.enrichmentSummary != nil },
            set: { isPresented in
                if !isPresented {
                    store.enrichmentSummary = nil
                }
            }
        )
    }

    private func showAIServicePreflight() {
        aiServiceStatus = nil
        isShowingAIServicePreflight = true
        checkAIService()
    }

    private func checkAIService() {
        guard !isCheckingAIService else { return }

        isCheckingAIService = true
        aiServiceStatus = nil

        Task {
            let status = await store.checkLocalAIService()

            await MainActor.run {
                aiServiceStatus = status
                isCheckingAIService = false
            }
        }
    }

    private func importBookmarks() {
        let panel = NSOpenPanel()
        panel.title = "Import Chrome Bookmarks"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.nameFieldStringValue = "Bookmarks"

        if panel.runModal() == .OK, let url = panel.url {
            store.importBookmarksFile(url)
        }
    }

    private func exportBookmarks() {
        let panel = NSSavePanel()
        panel.title = "Export Bookmarks"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "ultimate-organizer-bookmarks.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportBookmarks(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct ImportProgressBar: View {
    var progress: BookmarkImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.currentItemTitle ?? "Importing bookmarks")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if progress.totalItems > 0 {
                    Text("\(progress.processedItems) of \(progress.totalItems)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if progress.totalItems > 0 {
                ProgressView(value: progress.fractionCompleted, total: 1)
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: 0.03, total: 1)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct EnrichmentSummaryView: View {
    var summary: BookmarkEnrichmentSummary
    var closeAction: () -> Void
    var reviewAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 34))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Enrichment Summary")
                            .font(.title2.bold())
                        Text("Changes, discoveries, statistics, and cache usage from the latest processing run.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    SummaryMetric(title: "Processed", value: summary.totalBookmarks)
                    SummaryMetric(title: "Enriched", value: summary.enrichedCount)
                    SummaryMetric(title: "From Cache", value: summary.cachedEnrichmentCount)
                    SummaryMetric(title: "New AI Calls", value: summary.freshEnrichmentCount)
                    SummaryMetric(title: "Title Changes", value: summary.changedTitleCount)
                    SummaryMetric(title: "Folder Moves", value: summary.changedFolderCount)
                }

                HStack(alignment: .top, spacing: 16) {
                    SummarySection(title: "Insights", systemImage: "lightbulb") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(summary.insights, id: \.self) { insight in
                                Label(insight, systemImage: "checkmark")
                                    .labelStyle(.titleAndIcon)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    SummarySection(title: "Top Proposed Folders", systemImage: "folder") {
                        VStack(alignment: .leading, spacing: 7) {
                            if summary.topFolders.isEmpty {
                                Text("No folder destinations were proposed.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(summary.topFolders) { folder in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(folder.name)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Text("\(folder.count)")
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                }

                if summary.failedCount > 0 || summary.duplicateCount > 0 || summary.unchangedCount > 0 {
                    HStack(spacing: 8) {
                        if summary.failedCount > 0 {
                            SummaryPill(title: "Failed", value: summary.failedCount, color: .orange)
                        }

                        if summary.duplicateCount > 0 {
                            SummaryPill(title: "Duplicates", value: summary.duplicateCount, color: .purple)
                        }

                        if summary.unchangedCount > 0 {
                            SummaryPill(title: "Already Clean", value: summary.unchangedCount, color: .secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 680)

            Divider()

            HStack {
                Button("Close", role: .cancel, action: closeAction)

                Spacer()

                Button("Review Changes", action: reviewAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .background(.regularMaterial)
    }
}

private struct SummaryMetric: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .font(.title2.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SummarySection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SummaryPill: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }
}

private struct AIServicePreflightView: View {
    var status: LocalAIServiceStatus?
    var isChecking: Bool
    var retryAction: () -> Void
    var cancelAction: () -> Void
    var startAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 34))
                    .foregroundStyle(statusColor)
                    .frame(width: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isChecking {
                ProgressView("Checking configured local AI endpoint...")
                    .controlSize(.small)
            } else if let status {
                VStack(alignment: .leading, spacing: 10) {
                    AIServiceStatusRow(label: "Backend", value: status.backendName)
                    AIServiceStatusRow(label: "Endpoint", value: status.endpoint)
                    AIServiceStatusRow(label: "Configured model", value: status.configuredModel)

                    if status.isAvailable {
                        AIServiceStatusRow(
                            label: "Model status",
                            value: status.isConfiguredModelAvailable ? "Available" : "Not listed by server"
                        )

                        if !status.availableModels.isEmpty {
                            AIServiceStatusRow(label: "Server models", value: modelSummary(status.availableModels))
                        }
                    }

                    if let message = status.message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(status.isAvailable ? Color.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Button("Cancel", role: .cancel, action: cancelAction)

                Spacer()

                Button("Check Again", action: retryAction)
                    .disabled(isChecking)

                Button("Start Processing", action: startAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isChecking || status?.isAvailable != true)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        if isChecking { return "Checking Local AI Server" }
        guard let status else { return "Local AI Server Check" }
        return status.isAvailable ? "Local AI Server Ready" : "Local AI Server Not Found"
    }

    private var subtitle: String {
        if isChecking {
            return "The app is querying Ollama and LM Studio-compatible endpoints before starting enrichment."
        }

        guard let status else {
            return "Check the configured endpoint before starting AI enrichment."
        }

        if status.isAvailable {
            return "The app received a response and can start AI enrichment."
        }

        return "Start Ollama or LM Studio, confirm the endpoint in Settings, then check again."
    }

    private var statusIcon: String {
        if isChecking { return "waveform.path.ecg" }
        return status?.isAvailable == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if isChecking { return .secondary }
        return status?.isAvailable == true ? .green : .orange
    }

    private func modelSummary(_ models: [String]) -> String {
        let shownModels = models.prefix(5).joined(separator: ", ")
        let remainingCount = models.count - min(models.count, 5)
        return remainingCount > 0 ? "\(shownModels), +\(remainingCount) more" : shownModels
    }
}

private struct AIServiceStatusRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case review
    case duplicates
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .review: "Review"
        case .duplicates: "Duplicates"
        case .safety: "Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "bookmark"
        case .review: "square.split.2x1"
        case .duplicates: "doc.on.doc"
        case .safety: "internaldrive"
        }
    }
}
