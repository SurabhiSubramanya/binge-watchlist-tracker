#if DEBUG
import Foundation
import SwiftData

/// Sample titles for SwiftUI `#Preview`s.
///
/// This used to also seed a *real* store behind a `-seed-sample-library` launch
/// argument, because before Subtask 7 there was no way to get anything into the
/// library at all. Titles can be added for real now, so that path is gone — the
/// only remaining job is giving previews something to draw.
enum SampleLibrary {

    /// An in-memory container, so a preview can never touch the real store.
    @MainActor
    static var previewContainer: ModelContainer {
        let container = try! ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for item in items() {
            container.mainContext.insert(item)
        }
        return container
    }

    /// Covers the cases that break a grid: both media types, both watch statuses,
    /// a future release date (the "Upcoming" badge), a title with no poster (the
    /// artwork fallback), and one with no release date at all (the nil-date sort
    /// edge).
    ///
    /// Every `posterPath` here returns HTTP 200 from TMDB's CDN. A made-up path
    /// 404s and renders as the fallback — which looks exactly like a broken
    /// `AsyncImage`, and did once.
    private static func items() -> [MediaItem] {
        [
            MediaItem(
                tmdbId: 693134,
                mediaType: .movie,
                title: "Dune: Part Two",
                overview: "Paul Atreides unites with the Fremen to wage war against House Harkonnen.",
                posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
                releaseDate: ReleaseDate.parse("2024-02-27"),
                watchStatus: .wantToWatch
            ),
            MediaItem(
                tmdbId: 1234821,
                mediaType: .movie,
                title: "An Unannounced Sequel",
                overview: "Not out yet.",
                posterPath: nil,
                releaseDate: ReleaseDate.parse("2026-12-18"),
                watchStatus: .wantToWatch
            ),
            MediaItem(
                tmdbId: 999001,
                mediaType: .tv,
                title: "Something With No Date",
                overview: "TMDB doesn't know when this airs.",
                posterPath: nil,
                releaseDate: nil,
                watchStatus: .wantToWatch
            ),
            MediaItem(
                tmdbId: 872585,
                mediaType: .movie,
                title: "Oppenheimer",
                overview: "The story of J. Robert Oppenheimer and the atomic bomb.",
                posterPath: "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg",
                releaseDate: ReleaseDate.parse("2023-07-19"),
                watchStatus: .watched
            ),
            // A returning series with a dated next season — the grid shows the
            // "Upcoming" badge (isUpcoming now tracks the next season), and the
            // detail meta line reads "TV · 2022 · 2 seasons · Returning · Next: …".
            MediaItem(
                tmdbId: 95396,
                mediaType: .tv,
                title: "Severance",
                overview: "Mark leads a team whose memories have been surgically divided.",
                posterPath: "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg",
                releaseDate: ReleaseDate.parse("2022-02-18"),
                numberOfSeasons: 2,
                seriesStatus: "Returning",
                lastAirDate: ReleaseDate.parse("2025-03-21"),
                nextReleaseDate: ReleaseDate.parse("2027-01-16"),
                nextSeasonNumber: 3,
                watchStatus: .wantToWatch
            ),
            // A concluded series — the grid caption shows the run span "2008–2013"
            // rather than a lone premiere year.
            MediaItem(
                tmdbId: 1396,
                mediaType: .tv,
                title: "Breaking Bad",
                overview: "A chemistry teacher diagnosed with cancer turns to making meth.",
                posterPath: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg",
                releaseDate: ReleaseDate.parse("2008-01-20"),
                numberOfSeasons: 5,
                seriesStatus: "Ended",
                lastAirDate: ReleaseDate.parse("2013-09-29"),
                watchStatus: .watched
            )
        ]
    }
}
#endif
