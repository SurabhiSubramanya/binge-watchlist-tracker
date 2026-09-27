import Foundation
import Testing
@testable import Binge

/// The detail-screen meta line for TV (`MediaItem.detailMetaLine`) across the
/// states Option A has to read well in: ended, returning-with-next,
/// returning-without-next, single-season, not-premiered, sparse, and movie.
///
/// Assertions that can't move with locale — run spans, season counts, status —
/// are pinned exactly; the "Next" component embeds a locale-formatted date, so
/// those are checked by prefix + year rather than an exact string. The upcoming
/// cases use a far-future year so `isUpcoming` (which compares to *today*) can't
/// flip the test on some future run date.
@Suite("TV detail meta line")
struct SeasonMetaTests {

    private func tv(
        premiere: String? = nil,
        last: String? = nil,
        seasons: Int? = nil,
        status: String? = nil,
        next: String? = nil,
        nextSeason: Int? = nil
    ) -> MediaItem {
        MediaItem(
            tmdbId: 1, mediaType: .tv, title: "A Show",
            releaseDate: ReleaseDate.parse(premiere),
            numberOfSeasons: seasons,
            seriesStatus: status,
            lastAirDate: ReleaseDate.parse(last),
            nextReleaseDate: ReleaseDate.parse(next),
            nextSeasonNumber: nextSeason
        )
    }

    @Test("an ended series shows a closed run span, season count, and status")
    func ended() {
        let show = tv(premiere: "2008-01-20", last: "2013-09-29", seasons: 5, status: "Ended")
        #expect(show.runSpanText == "2008–2013")
        #expect(show.seasonCountText == "5 seasons")
        // Fully locale-stable — no formatted date, no "Next".
        #expect(show.detailMetaLine == "TV · 2008–2013 · 5 seasons · Ended")
    }

    @Test("a returning series leads with the premiere year and appends the next season")
    func returningWithNext() {
        let show = tv(premiere: "2022-02-18", last: "2025-03-21", seasons: 2,
                      status: "Returning", next: "2999-01-16", nextSeason: 3)
        // Not concluded → premiere year, not a span, even though last_air_date exists.
        #expect(show.runSpanText == "2022")
        #expect(show.nextReleaseText?.hasPrefix("Next: Season 3, ") == true)
        let line = show.detailMetaLine
        #expect(line.hasPrefix("TV · 2022 · 2 seasons · Returning · Next: Season 3, "))
        #expect(line.contains("2999"))
    }

    @Test("a returning series with no dated next season omits the Next component")
    func returningWithoutNext() {
        let show = tv(premiere: "2016-07-15", seasons: 3, status: "Returning")
        #expect(show.nextReleaseText == nil)
        #expect(show.detailMetaLine == "TV · 2016 · 3 seasons · Returning")
    }

    @Test("one season is singular")
    func singleSeason() {
        #expect(tv(seasons: 1).seasonCountText == "1 season")
        #expect(tv(seasons: 0).seasonCountText == nil, "zero seasons is not worth saying")
        #expect(tv(seasons: nil).seasonCountText == nil)
    }

    @Test("a series that began and ended the same year shows a single year, not a span")
    func concludedSameYear() {
        let show = tv(premiere: "2020-01-05", last: "2020-12-20", seasons: 1, status: "Ended")
        #expect(show.runSpanText == "2020")
        #expect(show.detailMetaLine == "TV · 2020 · 1 season · Ended")
    }

    @Test("a next date that has already passed is not shown")
    func pastNextIsHidden() {
        let show = tv(premiere: "2016-07-15", seasons: 3, status: "Returning",
                      next: "2000-01-01", nextSeason: 4)
        #expect(show.nextReleaseText == nil)
        #expect(!show.detailMetaLine.contains("Next:"))
    }

    @Test("a sparse series with no season data or dates falls back to the plain line")
    func sparseFallsBack() {
        let bare = tv()  // no premiere, no season data at all
        #expect(bare.detailMetaLine == "TV · Release date unknown")
    }

    @Test("a movie keeps the type · date line and never mentions seasons")
    func movieUnchanged() {
        let movie = MediaItem(
            tmdbId: 2, mediaType: .movie, title: "A Film",
            releaseDate: ReleaseDate.parse("2024-02-27")
        )
        let line = movie.detailMetaLine
        #expect(line.hasPrefix("Movie · "))
        #expect(!line.contains("season"))
        #expect(!line.contains("Next:"))
        // An undated movie still degrades gracefully.
        let undated = MediaItem(tmdbId: 3, mediaType: .movie, title: "TBD")
        #expect(undated.detailMetaLine == "Movie · Release date unknown")
    }
}
