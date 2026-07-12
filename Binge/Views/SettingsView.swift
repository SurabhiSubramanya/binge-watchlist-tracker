import SwiftUI

/// Where the user pastes their TMDB token and picks the region streaming
/// availability is looked up for. Everything here writes straight through
/// ``AppSettings`` — token to the Keychain, region to `UserDefaults`.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// The in-progress token. Deliberately *not* seeded from the stored token:
    /// a saved secret is shown masked, never handed back to a text field.
    @State private var tokenDraft = ""
    @State private var isEditingToken = false

    var body: some View {
        NavigationStack {
            Form {
                tokenSection
                regionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.bingeGround)
        }
    }

    // MARK: - Token

    @ViewBuilder
    private var tokenSection: some View {
        Section {
            if settings.isConfigured && !isEditingToken {
                LabeledContent {
                    Text(maskedToken)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Token saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                Button("Replace token") {
                    tokenDraft = ""
                    isEditingToken = true
                }

                Button("Remove token", role: .destructive) {
                    settings.clearToken()
                    tokenDraft = ""
                }
            } else {
                SecureField("Paste your Read Access Token", text: $tokenDraft)
                    .font(.callout.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(saveToken)

                Button("Save token", action: saveToken)
                    .disabled(!canSaveToken)

                if settings.isConfigured {
                    Button("Cancel", role: .cancel) {
                        tokenDraft = ""
                        isEditingToken = false
                    }
                }
            }
        } header: {
            Text("TMDB API token")
        } footer: {
            Text(settings.isConfigured
                 ? "Stored in the iOS Keychain — never in plain text, and never synced off this device."
                 : "Binge needs a TMDB token to search titles, load artwork, and look up where things stream.")
        }
    }

    private var canSaveToken: Bool {
        !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveToken() {
        guard canSaveToken else { return }
        // AppSettings trims and writes through to the Keychain on assignment.
        settings.tmdbToken = tokenDraft
        tokenDraft = ""
        isEditingToken = false
    }

    /// Last four characters only — enough to tell two tokens apart, not enough
    /// to be worth shoulder-surfing.
    private var maskedToken: String {
        "••••\(settings.tmdbToken.suffix(4))"
    }

    // MARK: - Region

    private var regionSection: some View {
        @Bindable var settings = settings

        return Section {
            Picker("Region", selection: $settings.region) {
                ForEach(Self.regionCodes, id: \.self) { code in
                    Text(Self.regionName(code)).tag(code)
                }
            }
        } header: {
            Text("Streaming region")
        } footer: {
            Text("Streaming services differ by country. Binge looks up availability for \(settings.regionDisplayName).")
        }
    }

    /// Every two-letter ISO 3166-1 region, sorted by the name we actually show.
    private static let regionCodes: [String] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .sorted { regionName($0) < regionName($1) }

    private static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                Label("Get a token from TMDB", systemImage: "arrow.up.right.square")
            }
        } footer: {
            Text("Binge uses TMDB for artwork, release dates, and streaming availability. Create a free account, then copy the **API Read Access Token** (the long v4 one — not the short v3 API key).")
        }
    }
}

#Preview("Needs token") {
    SettingsView()
        .environment(AppSettings.preview())
        .preferredColorScheme(.dark)
}

#Preview("Token saved") {
    SettingsView()
        .environment(AppSettings.preview(token: "eyJhbGciOiJIUzI1NiJ9.example.t0k3n", region: "GB"))
        .preferredColorScheme(.dark)
}
