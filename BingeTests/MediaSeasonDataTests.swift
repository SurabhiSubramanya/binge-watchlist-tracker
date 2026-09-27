import Foundation
import Testing
@testable import Binge

/// `MediaItem.applySeasonData(from:)` — the shared mapping both write paths
/// (`SearchView.enrich` on add, `MediaDetailView.refresh` on open) run through.
///
/// Decodes a real fixture and pushes it through the whole decode → normalize →
/// apply chain, so a field landing in the wrong property (the one silent way this
/// wiring breaks) fails here rather than showing the wrong date on the phone.
@Suite("Applying season data to a MediaItem")
struct MediaSeasonDataTests {

    private func decodeDetails(_ data: Data, as type: MediaType) throws -> TMDBTitleDetails {
        try TMDBService.decoder
            .decode(TMDBDetailsResponse.self, from: data)
            .normalized(mediaType: type)
    }

    @Test("a returning show's season data lands on the right fields, status as a label")
    func appliesReturning() throws {
        let details = try decodeDetails(TMDBFixtures.tvDetailsReturning, as: .tv)
        let item = MediaItem(
            tmdbId: 95396, mediaType: .tv, title: "Severance",
            releaseDate: ReleaseDate.parse("2022-02-18")
        )
        item.applySeasonData(from: details)

        #expect(item.numberOfSeasons == 2)
        #expect(item.seriesStatus == "Returning", "stored as the display label, not \"Returning Series\"")
        #expect(item.lastAirDate == ReleaseDate.parse("2025-03-21"))
        #expect(item.nextReleaseDate == ReleaseDate.parse("2027-01-16"))
        #expect(item.nextSeasonNumber == 3)
        // The payoff: the item now keys its Upcoming tag + reminder off the next season.
        #expect(item.effectiveReleaseDate == ReleaseDate.parse("2027-01-16"))
        #expect(item.isUpcoming)
    }

    @Test("an ended show carries no next date, so it's not upcoming")
    func appliesEnded() throws {
        let details = try decodeDetails(TMDBFixtures.tvDetailsEnded, as: .tv)
        let item = MediaItem(
            tmdbId: 1396, mediaType: .tv, title: "Breaking Bad",
            releaseDate: ReleaseDate.parse("2008-01-20")
        )
        item.applySeasonData(from: details)

        #expect(item.numberOfSeasons == 5)
        #expect(item.seriesStatus == "Ended")
        #expect(item.lastAirDate == ReleaseDate.parse("2013-09-29"))
        #expect(item.nextReleaseDate == nil)
        #expect(item.nextSeasonNumber == nil)
        #expect(item.effectiveReleaseDate == ReleaseDate.parse("2008-01-20"), "falls back to the premiere")
        #expect(!item.isUpcoming)
    }

    @Test("a movie's empty season data clears the fields rather than inventing any")
    func appliesMovie() throws {
        let details = try decodeDetails(TMDBFixtures.movieDetails, as: .movie)
        let item = MediaItem(
            tmdbId: 693134, mediaType: .movie, title: "Dune: Part Two",
            releaseDate: ReleaseDate.parse("2024-02-27")
        )
        item.applySeasonData(from: details)

        #expect(item.numberOfSeasons == nil)
        #expect(item.seriesStatus == nil)
        #expect(item.lastAirDate == nil)
        #expect(item.nextReleaseDate == nil)
        #expect(item.nextSeasonNumber == nil)
        #expect(item.effectiveReleaseDate == ReleaseDate.parse("2024-02-27"))
    }
}
