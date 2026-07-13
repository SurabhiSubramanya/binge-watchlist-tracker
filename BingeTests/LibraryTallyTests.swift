import Foundation
import Testing
@testable import Binge

/// The Watched tally under the Library grid.
///
/// Small sums, but each one encodes a decision that could just as easily have gone
/// the other way — that Want to Watch is excluded, and that the type filter doesn't
/// touch the numbers. Those are the things worth pinning, not the arithmetic.
@Suite("Library tally")
struct LibraryTallyTests {

    private func item(
        _ title: String,
        _ mediaType: MediaType,
        status: WatchStatus,
        id: Int = Int.random(in: 1...1_000_000)
    ) -> MediaItem {
        MediaItem(tmdbId: id, mediaType: mediaType, title: title, watchStatus: status)
    }

    @Test("films and series are counted separately")
    func countsEachTypeSeparately() {
        let tally = LibraryView.Tally([
            item("Oppenheimer", .movie, status: .watched),
            item("Arrival", .movie, status: .watched),
            item("Severance", .tv, status: .watched)
        ])

        #expect(tally == LibraryView.Tally(movies: 2, tv: 1))
    }

    /// The whole point of the line: it's what you've *finished*, not what you've
    /// piled up. A backlog counted next to it would be a different — and much less
    /// welcome — fact.
    @Test("the backlog is not counted")
    func ignoresWantToWatch() {
        let tally = LibraryView.Tally([
            item("Oppenheimer", .movie, status: .watched),
            item("Dune: Part Two", .movie, status: .wantToWatch),
            item("Severance", .tv, status: .watched),
            item("The Bear", .tv, status: .wantToWatch)
        ])

        #expect(tally == LibraryView.Tally(movies: 1, tv: 1))
    }

    /// The totals are meant to be independent of the type filter — the tally is a
    /// fact about the library, not about the grid.
    ///
    /// What that actually rests on is the *call site*: `LibraryView` hands `Tally` the
    /// full `items`, not `visibleItems`. This test can't reach in and check that (it
    /// would need to drive the view), so it pins the next best thing: that feeding
    /// `Tally` a filtered list — the mistake — visibly changes the answer. That's why
    /// `Tally.init` carries a comment saying not to.
    @Test("feeding the tally a filtered list is exactly the mistake to avoid")
    func filteredInputChangesTheAnswer() {
        let items = [
            item("Oppenheimer", .movie, status: .watched),
            item("Severance", .tv, status: .watched)
        ]

        let whole = LibraryView.Tally(items)
        let filteredToMovies = LibraryView.Tally(
            items.filter { LibraryView.TypeFilter.movies.matches($0.mediaType) }
        )

        #expect(whole == LibraryView.Tally(movies: 1, tv: 1))
        #expect(filteredToMovies == LibraryView.Tally(movies: 1, tv: 0))
        #expect(whole != filteredToMovies, "the two must differ — otherwise this guards nothing")
    }

    @Test("an empty Watched list has nothing to say")
    func emptyWhenNothingWatched() {
        let tally = LibraryView.Tally([item("Dune: Part Two", .movie, status: .wantToWatch)])

        #expect(tally.isEmpty)
        #expect(tally == LibraryView.Tally(movies: 0, tv: 0))
    }

    @Test("a library with only films still counts as having something")
    func notEmptyWithOnlyOneType() {
        let tally = LibraryView.Tally([item("Oppenheimer", .movie, status: .watched)])

        #expect(!tally.isEmpty)
        #expect(tally == LibraryView.Tally(movies: 1, tv: 0))
    }
}
