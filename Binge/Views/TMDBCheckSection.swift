#if DEBUG
import SwiftUI

/// Temporary Subtask-4 verification surface.
///
/// The TMDB service has no UI of its own until Search lands in Subtask 7, so
/// this DEBUG-only Settings section is how it gets exercised against **live**
/// TMDB with a real token — a full `search → details → watch/providers`
/// round-trip, which is the one thing saved sample JSON can't prove.
///
/// Deleted in Subtask 7, when the real Search screen makes it redundant.
struct TMDBCheckSection: View {
    @Environment(AppSettings.self) private var settings

    @State private var state = CheckState.idle

    /// Not `State` — that name collides with SwiftUI's `@State` wrapper.
    enum CheckState {
        case idle
        case running
        case passed(String)
        case failed(String)
    }

    var body: some View {
        Section {
            Button("Test TMDB connection") {
                Task { await runCheck() }
            }
            .disabled(!settings.isConfigured || isRunning)

            switch state {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Calling TMDB…").foregroundStyle(.secondary)
                }
            case .passed(let summary):
                Text(summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.green)
            case .failed(let message):
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Runs a live search → details → watch-providers round-trip against TMDB. Temporary; removed when Search lands.")
        }
    }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private func runCheck() async {
        state = .running

        let service = TMDBService(settings: settings)
        do {
            let results = try await service.searchMulti(query: "dune")
            guard let first = results.first else {
                state = .failed("✗ search returned nothing")
                return
            }

            let details = try await service.details(for: first.tmdbId, mediaType: first.mediaType)
            let providers = try await service.watchProviders(
                for: first.tmdbId,
                mediaType: first.mediaType,
                region: settings.region
            )

            let year = details.releaseDate
                .map { String(Calendar.current.component(.year, from: $0)) } ?? "—"
            let streams = providers.filter { $0.offer == .stream }.count

            state = .passed("""
            ✓ search: \(results.count) titles (people dropped)
            ✓ details: \(details.title) · \(year) · \(details.genres.count) genres
            ✓ providers: \(providers.count) in \(settings.region) (\(streams) streaming)
            """)
        } catch {
            // Exercises the typed-error path too: a bad token should read as a
            // token problem, not a generic failure.
            let hint = (error as? TMDBError)?.isTokenProblem == true ? " → check Settings" : ""
            state = .failed("✗ \(error.localizedDescription)\(hint)")
        }
    }
}
#endif
