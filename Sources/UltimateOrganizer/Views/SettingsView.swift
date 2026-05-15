import SwiftUI
import UltimateOrganizerCore

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsView()

            Divider()

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
    }
}

struct SettingsView: View {
    @AppStorage("ollamaModel") private var ollamaModel = "llama3.1"
    @AppStorage("ollamaEndpoint") private var ollamaEndpoint = "http://localhost:11434"
    @AppStorage("ollamaTimeout") private var ollamaTimeout = 60
    @AppStorage("localAIContextWindow") private var localAIContextWindow = 4096
    @AppStorage("enableDeepFetch") private var enableDeepFetch = false
    @AppStorage("importOnLaunch") private var importOnLaunch = true
    @AppStorage("preferredChromeProfile") private var preferredChromeProfile = "Default"
    @AppStorage("showOnboardingWizard") private var showOnboardingWizard = true
    @AppStorage("requireChromeClosed") private var requireChromeClosed = true
    @AppStorage("createBackupBeforeWrite") private var createBackupBeforeWrite = true
    @AppStorage("preserveBookmarksBarFolders") private var preserveBookmarksBarFolders = true
    @AppStorage("skipDeleteConfirmation") private var skipDeleteConfirmation = false
    @State private var chromeProfiles = ChromeProfileLocator.defaultProfiles

    var body: some View {
        TabView {
            SettingsPane(title: "Import") {
                SettingsRow("Chrome profile") {
                    Picker("", selection: $preferredChromeProfile) {
                        ForEach(chromeProfiles) { profile in
                            Text(profile.pickerTitle).tag(profile.directoryName)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .help("Chrome profile directory and display name")
                }

                SettingsRow {
                    Toggle("Import bookmarks on launch", isOn: $importOnLaunch)
                        .toggleStyle(.checkbox)
                }

                SettingsRow {
                    Toggle("Show onboarding wizard at launch", isOn: $showOnboardingWizard)
                        .toggleStyle(.checkbox)
                }

                SettingsRow {
                    HStack(spacing: 6) {
                        Toggle("Use Deep Mode page fetching", isOn: $enableDeepFetch)
                            .toggleStyle(.checkbox)

                        InfoTip(text: "Deep Mode fetches bookmark pages while processing so local AI can use page content, not only titles and URLs. It is slower and may contact every bookmarked site.")
                    }
                }
            }
            .tabItem {
                Text("General")
            }

            SettingsPane(title: "Local AI") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Ollama, LM Studio, or another OpenAI-compatible local server", systemImage: "cpu")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow("Endpoint") {
                            TextField("", text: $ollamaEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                                .help("Use an Ollama endpoint like http://localhost:11434 or an OpenAI-compatible endpoint like http://localhost:1234/v1")
                        }

                        SettingsRow("Model") {
                            TextField("", text: $ollamaModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }

                        SettingsRow("Context") {
                            HStack(spacing: 10) {
                                Slider(
                                    value: contextWindowBinding,
                                    in: 2048...32768,
                                    step: 1024
                                )
                                .frame(width: 190)
                                .help("Requested context window for Ollama generation. LM Studio context is usually controlled by the loaded model/server settings.")

                                Text("\(localAIContextWindow.formatted()) tokens")
                                    .font(.callout.monospacedDigit())
                                    .frame(width: 96, alignment: .trailing)
                            }
                        }

                        SettingsRow("Timeout") {
                            Stepper(value: $ollamaTimeout, in: 10...300, step: 10) {
                                Text("\(ollamaTimeout) seconds")
                                    .monospacedDigit()
                                    .frame(width: 88, alignment: .trailing)
                            }
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .tabItem {
                Text("AI")
            }

            SettingsPane(title: "Apply Changes") {
                SettingsRow {
                    Toggle("Require Chrome to be closed before applying changes", isOn: $requireChromeClosed)
                        .toggleStyle(.checkbox)
                }

                SettingsRow {
                    Toggle("Create a backup before writing bookmarks", isOn: $createBackupBeforeWrite)
                        .toggleStyle(.checkbox)
                }

                SettingsRow {
                    HStack(spacing: 6) {
                        Toggle("Preserve folders on the bookmarks toolbar", isOn: $preserveBookmarksBarFolders)
                            .toggleStyle(.checkbox)

                        InfoTip(text: "Keeps existing folders and groups under Chrome's Bookmarks Bar even when their contents are removed or reorganized. This is on by default.")
                    }
                }

                SettingsRow {
                    Toggle("Skip delete confirmation prompts", isOn: $skipDeleteConfirmation)
                        .toggleStyle(.checkbox)
                }
            }
            .tabItem {
                Text("Storage")
            }
        }
        .frame(width: 560, height: 340)
        .scenePadding()
        .onAppear {
            chromeProfiles = ChromeProfileLocator().discoverProfiles()
        }
    }

    private var contextWindowBinding: Binding<Double> {
        Binding(
            get: { Double(localAIContextWindow) },
            set: { localAIContextWindow = Int($0) }
        )
    }
}

private struct SettingsPane<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }

            Spacer()
        }
        .padding(.top, 18)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsRow<Content: View>: View {
    private var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let title {
                Text(title)
                    .frame(width: 120, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }

            content

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
    }
}

private struct InfoTip: View {
    var text: String

    var body: some View {
        Image(systemName: "info.circle")
            .imageScale(.small)
            .foregroundStyle(.secondary)
            .accessibilityLabel("More information")
            .help(text)
    }
}
