#if DEBUG
import Foundation
import SwiftData

/// Temporary Subtask-6 verification data.
///
/// The Library grid can't be *seen* until something is in the library, and the
/// add flow doesn't exist until Subtask 7. So this seeds a handful of titles —
/// but only when the app is launched with `-seed-sample-library`, which is how
/// the Simulator run for this subtask gets a populated grid to screenshot.
///
/// A normal launch never touches this, so a real device library stays untouched.
/// Deleted in Subtask 7, once titles can be added for real.
enum SampleLibrary {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seed-sample-library")
    }

    /// Inserts the sample titles, but only into an empty store — so relaunching
    /// with the flag doesn't pile up duplicates.
    static func seed(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        guard existing.isEmpty else { return }

        for item in items() {
            context.insert(item)
        }
        try? context.save()
    }

    /// An in-memory container for `#Preview`s.
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

    /// Deliberately covers the cases that break a grid:
    /// - both media types and both watch statuses (so the segment + filter do something),
    /// - a **future** release date (the "Upcoming" badge),
    /// - a title with **no poster** (the artwork fallback),
    /// - a title with **no release date at all** (the nil-date sort edge),
    /// - and at least one *real* poster in **each** tab, so a tab full of
    ///   fallbacks can't be mistaken for working artwork.
    ///
    /// Every `posterPath` below was checked to return HTTP 200 from TMDB's CDN.
    /// A made-up path 404s and silently renders as the fallback — which looks
    /// exactly like a broken `AsyncImage`.
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
            // Future date → the "Upcoming" badge. No poster either, so it
            // exercises the artwork fallback at the same time.
            MediaItem(
                tmdbId: 1234821,
                mediaType: .movie,
                title: "An Unannounced Sequel",
                overview: "Not out yet.",
                posterPath: nil,
                releaseDate: ReleaseDate.parse("2026-12-18"),
                watchStatus: .wantToWatch
            ),
            // No release date at all — the sort must sink this deliberately
            // rather than treating it as 1970.
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
            MediaItem(
                tmdbId: 95396,
                mediaType: .tv,
                title: "Severance",
                overview: "Mark leads a team whose memories have been surgically divided.",
                posterPath: "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg",
                releaseDate: ReleaseDate.parse("2022-02-17"),
                watchStatus: .watched
            )
        ]
    }
}
#endif
