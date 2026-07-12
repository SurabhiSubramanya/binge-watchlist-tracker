import Foundation
import Testing
@testable import Binge

/// The Library's sort and filter rules.
///
/// These are pure functions, so they're tested directly rather than by driving
/// the grid — which is just as well, because the case most likely to be wrong
/// (a title with no release date) is invisible in a screenshot.
@Suite("Library sorting and filtering")
struct LibrarySortFilterTests {

    private func item(
        _ title: String,
        _ mediaType: MediaType = .movie,
        release: String? = nil,
        added: Date = .now,
        status: WatchStatus = .wantToWatch,
        id: Int = Int.random(in: 1...1_000_000)
    ) -> MediaItem {
        MediaItem(
            tmdbId: id,
            mediaType: mediaType,
            title: title,
            releaseDate: ReleaseDate.parse(release),
            watchStatus: status,
            dateAdded: added
        )
    }

    // MARK: - Sorting

    @Test("release-date sort is newest first, with unknown dates sunk to the bottom")
    func releaseDateSort() {
        let old = item("Old", release: "1999-01-01")
        let recent = item("Recent", release: "2024-02-27")
        let undated = item("Undated", release: nil)

        let sorted = [undated, old, recent]
            .sorted(by: LibraryView.SortOption.releaseDate.areInIncreasingOrder)

        // The bug this guards: a nil date defaulting to .distantPast (or 1970)
        // and silently leading the list.
        #expect(sorted.map(\.title) == ["Recent", "Old", "Undated"])
    }

    @Test("two undated titles fall back to title order, so the grid doesn't shuffle")
    func undatedTitlesAreStable() {
        let b = item("Beta", release: nil)
        let a = item("Alpha", release: nil)

        let sorted = [b, a].sorted(by: LibraryView.SortOption.releaseDate.areInIncreasingOrder)
        #expect(sorted.map(\.title) == ["Alpha", "Beta"])
    }

    @Test("titles sort naturally, so 2 comes before 10")
    func titleSortIsNatural() {
        let two = item("Episode 2")
        let ten = item("Episode 10")

        let sorted = [ten, two].sorted(by: LibraryView.SortOption.title.areInIncreasingOrder)
        // A plain `<` would put "Episode 10" first — string comparison, not numeric.
        #expect(sorted.map(\.title) == ["Episode 2", "Episode 10"])
    }

    @Test("recently added is newest first")
    func dateAddedSort() {
        let now = Date()
        let older = item("Older", added: now.addingTimeInterval(-3600))
        let newer = item("Newer", added: now)

        let sorted = [older, newer].sorted(by: LibraryView.SortOption.dateAdded.areInIncreasingOrder)
        #expect(sorted.map(\.title) == ["Newer", "Older"])
    }

    // MARK: - Filtering

    @Test("the type filter keeps only what it says")
    func typeFilter() {
        #expect(LibraryView.TypeFilter.all.matches(.movie))
        #expect(LibraryView.TypeFilter.all.matches(.tv))

        #expect(LibraryView.TypeFilter.movies.matches(.movie))
        #expect(!LibraryView.TypeFilter.movies.matches(.tv))

        #expect(LibraryView.TypeFilter.tv.matches(.tv))
        #expect(!LibraryView.TypeFilter.tv.matches(.movie))
    }

    // MARK: - Upcoming badge

    @Test("only a future-dated title is upcoming")
    func upcomingBadge() {
        let future = item("Future", release: "2099-01-01")
        let past = item("Past", release: "1999-01-01")
        let undated = item("Undated", release: nil)

        #expect(future.isUpcoming)
        #expect(!past.isUpcoming)
        // No date means no claim either way — it must not read as upcoming.
        #expect(!undated.isUpcoming)
    }
}
