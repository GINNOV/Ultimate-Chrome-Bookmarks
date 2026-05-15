import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private var copyrightYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    private let authorURL = URL(string: "https://about.me/marioesposito")!
    private let sourceURL = URL(string: "https://github.com/GINNOV/Ultimate-Chrome-Bookmarks")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                AppMark()

                VStack(spacing: 6) {
                    Text("Ultimate Organizer")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    Text("Bookmark cleanup with local AI")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    InfoPill(label: "Version", value: version)
                    InfoPill(label: "Build", value: build)
                }

                HStack(spacing: 16) {
                    Link(destination: authorURL) {
                        Label("Mario Esposito", systemImage: "person.crop.circle")
                    }

                    Link(destination: sourceURL) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                .buttonStyle(.link)
                .font(.callout)

                VStack(spacing: 8) {
                    Label("Runs locally with Ollama", systemImage: "cpu")
                    Label("Reviews changes before writing bookmarks", systemImage: "checkmark.shield")
                    Label("Designed for Chrome bookmark libraries", systemImage: "bookmark")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 34)
            }
            .padding(.top, 30)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(width: 460)

            Divider()

            HStack {
                Text("Copyright \(copyrightYear)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .background(.regularMaterial)
    }
}

private struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlAccentColor),
                            Color(nsColor: .systemTeal)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)

            Image(systemName: "bookmark.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
        .frame(width: 92, height: 92)
    }
}

private struct InfoPill: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}
