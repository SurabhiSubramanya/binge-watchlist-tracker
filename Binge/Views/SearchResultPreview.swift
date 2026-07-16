import SwiftUI

/// A read-only preview of a search hit, shown as a sheet *before* it's added — so
/// you can confirm it's the title you meant. It shows what the search row already
/// carries straight away (artwork, title, when it's out, what it's about), then
/// quietly enriches with genres and the fuller overview from the details endpoint.
///
/// The only things you can do from here are add it to a library or dismiss —
/// mutation and the SwiftData context stay in ``SearchView`` (which owns `add`),
/// so this view takes an `onAdd` closure rather than a `MediaItem`.
struct SearchResultPreview: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let result: TMDBSearchResult
    /// Whether this title is already tracked — decided by ``SearchView`` at present.
    let isInLibrary: Bool
    /// Adds `result` to the given library. ``SearchView`` runs the real insert +
    /// enrich; this view just dismisses afterwards.
    let onAdd: (WatchStatus) -> Void

    /// Not in a search row — pulled from the details endpoint on appear.
    @State private var genres: [String] = []
    /// The details overview is fuller than the search row's; prefer it once it lands.
    @State private var enrichedOverview: String?

    private var overviewText: String { enrichedOverview ?? result.overview }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bingeGround.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if !overviewText.isEmpty { overview }
                    }
                    .padding(.bottom, 24)
                }
                .safeAreaInset(edge: .bottom) { actionBar }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await enrich() }
        }
        // A "pop up" that lands at half height and expands if you want the rest.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackdropImage(backdropPath: result.backdropPath, posterPath: result.posterPath, height: 190)

            HStack(alignment: .top, spacing: 14) {
                MediaPosterView(
                    title: result.title,
                    posterPath: result.posterPath,
                    mediaType: result.mediaType,
                    showsCaption: false // the title is right beside it
                )
                .frame(width: 100)

                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isUpcoming {
                        Label("Upcoming", systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(.top, 2)
                    }

                    if !genres.isEmpty {
                        Text(genres.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, -30) // lift the poster over the backdrop's fade
        }
    }

    /// Type · release date — always the day TMDB published (see ``ReleaseDate``).
    private var metaLine: String {
        [result.mediaType.displayName, releaseDateText ?? "Release date unknown"]
            .joined(separator: " · ")
    }

    private var releaseDateText: String? {
        guard let date = result.releaseDate else { return nil }
        return ReleaseDate.formatted(date)
    }

    private var isUpcoming: Bool {
        guard let date = result.releaseDate else { return false }
        return ReleaseDate.isUpcoming(date)
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
                .foregroundStyle(.white)
            Text(overviewText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            if isInLibrary {
                Label("Already in your library", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                // `.plain` + an explicit background, drawn as the buttons they are,
                // so iOS's Button Shapes setting can't repaint them into tinted
                // system pills (the Fix 5 hazard).
                Button {
                    onAdd(.wantToWatch)
                    dismiss()
                } label: {
                    addLabel("Add to Want to Watch", systemImage: "bookmark.fill", filled: true)
                }
                .buttonStyle(.plain)

                Button {
                    onAdd(.watched)
                    dismiss()
                } label: {
                    addLabel("Add to Watched", systemImage: "checkmark.circle", filled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            // A hairline over the ground, so scrolling content meets the bar cleanly.
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                Color.bingeGround
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func addLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title).fontWeight(.semibold)
        }
        .font(.body)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(filled ? Color.black : Color.white)
        .background(
            filled ? Color.accentColor : Color.white.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Enrich

    /// Genres and the fuller overview aren't in a search row. Best-effort: a
    /// failure just leaves the search data on screen, which is enough to confirm.
    private func enrich() async {
        guard settings.isConfigured else { return }
        guard let details = try? await TMDBService(settings: settings)
            .details(for: result.tmdbId, mediaType: result.mediaType) else { return }

        genres = details.genres
        if !details.overview.isEmpty { enrichedOverview = details.overview }
    }
}

#Preview("Want to add") {
    Color.bingeGround
        .sheet(isPresented: .constant(true)) {
            SearchResultPreview(
                result: TMDBSearchResult(
                    tmdbId: 693134,
                    mediaType: .movie,
                    title: "Dune: Part Two",
                    overview: "Paul Atreides unites with Chani and the Fremen while seeking revenge against the conspirators who destroyed his family.",
                    posterPath: nil,
                    backdropPath: nil,
                    releaseDate: nil
                ),
                isInLibrary: false,
                onAdd: { _ in }
            )
        }
        .environment(AppSettings.preview(token: "preview-token"))
        .tint(.accentColor)
        .preferredColorScheme(.dark)
}
