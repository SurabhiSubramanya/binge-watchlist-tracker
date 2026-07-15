import SwiftData
import SwiftUI

/// Search TMDB and add titles to the library.
struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    /// Everything already in the library, so results can be marked as such.
    /// Only the unique keys are used — see `libraryKeys`.
    @Query private var libraryItems: [MediaItem]

    @State private var query = ""
    @State private var results: [TMDBSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: Error?

    /// The result awaiting a "want to watch / watched" choice.
    @State private var pendingAdd: TMDBSearchResult?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bingeGround.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies and TV shows")
            // `.task(id:)` cancels the in-flight run on every keystroke, which is
            // what makes the debounce below work.
            .task(id: query) { await runSearch() }
            // Tapping a result opens a read-only preview to confirm it's the right
            // title, *then* offers to add it — rather than jumping straight to an
            // add dialog with nothing but the name to go on.
            .sheet(item: $pendingAdd) { result in
                SearchResultPreview(
                    result: result,
                    isInLibrary: isInLibrary(result),
                    onAdd: { add(result, as: $0) }
                )
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if !settings.isConfigured {
            // The plan's hard requirement: no token must read as a clear,
            // actionable state — never a hang or an empty list.
            ContentUnavailableView {
                Label("No TMDB token", systemImage: "key.horizontal")
            } description: {
                Text("Add your TMDB token in Settings and you can search for anything.")
            }
        } else if let searchError {
            errorState(searchError)
        } else if isSearching && results.isEmpty {
            ProgressView().controlSize(.large)
        } else if trimmedQuery.isEmpty {
            ContentUnavailableView {
                Label("Search TMDB", systemImage: "magnifyingglass")
            } description: {
                Text("Find a movie or show, then add it to your library.")
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else {
            grid
        }
    }

    private func errorState(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Couldn't search", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            // A token problem can't be retried away — the fix is in Settings —
            // so only offer a retry when retrying could actually help.
            if (error as? TMDBError)?.isTokenProblem != true {
                Button("Try again") {
                    Task { await runSearch(skipDebounce: true) }
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(results) { result in
                    Button {
                        // Open the preview for any result — an already-added title
                        // still previews (it just says so, with no add buttons).
                        pendingAdd = result
                    } label: {
                        MediaPosterView(
                            title: result.title,
                            posterPath: result.posterPath,
                            mediaType: result.mediaType,
                            year: result.releaseDate.map { String(ReleaseDate.year(of: $0)) },
                            badge: badge(for: result),
                            badgeTint: isInLibrary(result) ? .green : .accentColor
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private func badge(for result: TMDBSearchResult) -> String? {
        if isInLibrary(result) { return "In Library" }
        if let date = result.releaseDate, ReleaseDate.isUpcoming(date) { return "Upcoming" }
        return nil
    }

    // MARK: - Searching

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runSearch(skipDebounce: Bool = false) async {
        guard !trimmedQuery.isEmpty else {
            results = []
            searchError = nil
            isSearching = false
            return
        }
        guard settings.isConfigured else { return }

        if !skipDebounce {
            // The debounce. Each keystroke restarts this task, so the sleep only
            // survives once typing pauses — TMDB never sees a request per letter.
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return // superseded by a newer keystroke
            }
        }

        isSearching = true
        defer { isSearching = false }

        do {
            results = try await TMDBService(settings: settings).searchMulti(query: trimmedQuery)
            searchError = nil
        } catch is CancellationError {
            return // superseded; leave the old results on screen rather than flashing
        } catch {
            searchError = error
            results = []
        }
    }

    // MARK: - Adding

    /// `TMDBSearchResult.id` is deliberately the same composite key `MediaItem`
    /// dedups on, so membership is a straight set lookup.
    private var libraryKeys: Set<String> {
        Set(libraryItems.map(\.uniqueKey))
    }

    private func isInLibrary(_ result: TMDBSearchResult) -> Bool {
        libraryKeys.contains(result.id)
    }

    private func add(_ result: TMDBSearchResult, as status: WatchStatus) {
        // Belt and braces: the UI blocks this, but `uniqueKey` is a unique
        // attribute and a duplicate insert would fail the save.
        guard !isInLibrary(result) else { return }

        let item = MediaItem(
            tmdbId: result.tmdbId,
            mediaType: result.mediaType,
            title: result.title,
            overview: result.overview,
            posterPath: result.posterPath,
            backdropPath: result.backdropPath,
            releaseDate: result.releaseDate,
            watchStatus: status
        )
        modelContext.insert(item)
        try? modelContext.save()

        // Genres and the streaming snapshot need two more round-trips, and the
        // title is already saved by now. Enrich in the background: if the network
        // drops, the user still has the title — just without providers yet, which
        // the detail screen re-fetches anyway.
        Task { await enrich(item, from: result) }
    }

    private func enrich(_ item: MediaItem, from result: TMDBSearchResult) async {
        let service = TMDBService(settings: settings)
        let region = settings.region

        if let details = try? await service.details(for: result.tmdbId, mediaType: result.mediaType) {
            item.genres = details.genres
            // Search results carry a shorter overview than the details endpoint.
            if !details.overview.isEmpty {
                item.overview = details.overview
            }
        }

        if let providers = try? await service.watchProviders(
            for: result.tmdbId,
            mediaType: result.mediaType,
            region: region
        ) {
            item.streamingProviders = providers
            item.providersRegion = region
            item.providersUpdatedAt = .now
        }

        try? modelContext.save()
    }
}

#Preview("Needs token") {
    SearchView()
        .environment(AppSettings.preview())
        .modelContainer(SampleLibrary.previewContainer)
        .preferredColorScheme(.dark)
}

#Preview("Ready to search") {
    SearchView()
        .environment(AppSettings.preview(token: "preview-token"))
        .modelContainer(SampleLibrary.previewContainer)
        .preferredColorScheme(.dark)
}
