import SwiftUI

struct OnboardingWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showOnboardingWizard: Bool
    @State private var selectedPage = 0

    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: pages[selectedPage].systemImage)
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .frame(width: 70, height: 70)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(pages[selectedPage].title)
                            .font(.title.bold())
                            .lineLimit(2)

                        Text(pages[selectedPage].subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 230, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(pages[selectedPage].steps, id: \.self) { step in
                        Label(step, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedPage ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 330, alignment: .topLeading)
            }
            .padding(28)
            .frame(width: 660, height: 360)

            Divider()

            HStack {
                Toggle("Show this wizard at launch", isOn: $showOnboardingWizard)
                    .toggleStyle(.checkbox)

                Spacer()

                Button("Back") {
                    selectedPage = max(0, selectedPage - 1)
                }
                .disabled(selectedPage == 0)

                Button(selectedPage == pages.count - 1 ? "Done" : "Next") {
                    if selectedPage == pages.count - 1 {
                        dismiss()
                    } else {
                        selectedPage += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
    }
}

private struct OnboardingPage {
    var title: String
    var subtitle: String
    var systemImage: String
    var steps: [String]

    static let all: [OnboardingPage] = [
        OnboardingPage(
            title: "Import Your Bookmarks",
            subtitle: "Start with the Chrome profile or a specific Bookmarks file.",
            systemImage: "square.and.arrow.down",
            steps: [
                "Use Import to choose a Chrome Bookmarks file manually.",
                "Set your preferred Chrome profile in Settings.",
                "The app keeps changes in a working set until you export or apply them."
            ]
        ),
        OnboardingPage(
            title: "Review Before Changing Anything",
            subtitle: "Use the review tables to inspect names, folders, duplicates, and links.",
            systemImage: "square.split.2x1",
            steps: [
                "Open Review to compare current and proposed bookmark names.",
                "Only URL cells open pages in the browser.",
                "Select one or more rows and use Delete to remove items from the working set."
            ]
        ),
        OnboardingPage(
            title: "Run Local AI Enrichment",
            subtitle: "Process bookmarks with a local model served by Ollama or LM Studio.",
            systemImage: "wand.and.sparkles",
            steps: [
                "Start Ollama or LM Studio before using Process.",
                "Set the endpoint, model, and timeout in Settings.",
                "Use Stop any time to cancel a long processing run."
            ]
        ),
        OnboardingPage(
            title: "Export Safely",
            subtitle: "Keep Chrome safe from conflicts and save your reviewed result.",
            systemImage: "internaldrive",
            steps: [
                "Check Storage before writing changes back to Chrome.",
                "Close Chrome before applying bookmark file changes.",
                "Bookmarks Bar folders and groups are preserved by default.",
                "Use Export to save a JSON review copy with original and proposed titles."
            ]
        )
    ]
}
