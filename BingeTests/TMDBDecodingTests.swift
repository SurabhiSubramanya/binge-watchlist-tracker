import Foundation
import Testing
@testable import Binge

/// Decoder tests for the TMDB layer (Subtask 4).
///
/// These run against saved sample JSON and decode through `TMDBService.decoder` —
/// the *real* decoder the app uses — so a change to its key strategy breaks these
/// rather than silently breaking the app.
@Suite("TMDB decoding")
struct TMDBDecodingTests {

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try TMDBService.decoder.decode(type, from: data)
    }

    // MARK: - search/multi

    @Test("search/multi drops person rows and keeps movie + tv")
    func searchDropsPeople() throws {
        let response = try Self.decode(TMDBSearchResponse.self, from: TMDBFixtures.searchMulti)
        #expect(response.results.count == 3, "all three raw rows should decode")

        let results = response.results.compactMap { $0.normalized() }
        #expect(results.count == 2, "the person row should be dropped")
        #expect(!results.contains { $0.tmdbId == 1190668 })
    }

    @Test("a movie row reads its title and date from title/release_date")
    func movieRowMapping() throws {
        let response = try Self.decode(TMDBSearchResponse.self, from: TMDBFixtures.searchMulti)
        let movie = try #require(response.results.compactMap { $0.normalized() }
            .first { $0.mediaType == .movie })

        #expect(movie.tmdbId == 693134)
        #expect(movie.title == "Dune: Part Two")
        #expect(movie.posterPath == "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg")
        #expect(movie.releaseDate == expectedDate(2024, 2, 27))
        // Same composite key MediaItem dedups on — Search relies on this.
        #expect(movie.id == "movie-693134")
    }

    @Test("a tv row reads its title and date from name/first_air_date")
    func tvRowMapping() throws {
        let response = try Self.decode(TMDBSearchResponse.self, from: TMDBFixtures.searchMulti)
        let show = try #require(response.results.compactMap { $0.normalized() }
            .first { $0.mediaType == .tv })

        #expect(show.tmdbId == 87739)
        #expect(show.title == "Dune: Prophecy")
        #expect(show.releaseDate == expectedDate(2024, 11, 17))
        // TMDB sent "" rather than null — that must become nil, not an empty path
        // that would build a URL straight to a 404.
        #expect(show.backdropPath == nil)
        #expect(show.id == "tv-87739")
    }

    // MARK: - details

    @Test("movie details decode with genre names flattened")
    func movieDetails() throws {
        let response = try Self.decode(TMDBDetailsResponse.self, from: TMDBFixtures.movieDetails)
        let details = response.normalized(mediaType: .movie)

        #expect(details.tmdbId == 693134)
        #expect(details.title == "Dune: Part Two")
        #expect(details.genres == ["Science Fiction", "Adventure"])
        #expect(details.releaseDate == expectedDate(2024, 2, 27))
    }

    @Test("tv details use name, and an empty air date is nil not a crash")
    func tvDetails() throws {
        let response = try Self.decode(TMDBDetailsResponse.self, from: TMDBFixtures.tvDetails)
        let details = response.normalized(mediaType: .tv)

        #expect(details.title == "Dune: Prophecy")
        #expect(details.genres == ["Sci-Fi & Fantasy"])
        #expect(details.releaseDate == nil)
        #expect(details.backdropPath == nil)
    }

    // MARK: - watch/providers

    @Test("providers collapse to stream/rent/buy without duplicate ids")
    func providerMapping() throws {
        let response = try Self.decode(TMDBWatchProvidersResponse.self, from: TMDBFixtures.watchProviders)
        let providers = try #require(response.results["US"]).streamingProviders()

        // Max is in BOTH flatrate and ads. Both collapse to .stream, so without
        // dedup we'd emit two providers sharing id "1899-stream".
        #expect(providers.count == 3)
        #expect(Set(providers.map(\.id)).count == providers.count, "ids must be unique")

        let max = try #require(providers.first { $0.providerId == 1899 })
        #expect(max.offer == .stream)
        // Kept the flatrate entry (priority 3), not the ads one (priority 9).
        #expect(max.displayPriority == 3)

        // Apple TV is in rent AND buy — genuinely different offers, both survive.
        let appleTV = providers.filter { $0.providerId == 2 }
        #expect(Set(appleTV.map(\.offer)) == [.rent, .buy])
    }

    @Test("providers are filtered to the requested region")
    func providerRegionFiltering() throws {
        let response = try Self.decode(TMDBWatchProvidersResponse.self, from: TMDBFixtures.watchProviders)

        // GB is in the payload but isn't what we asked for.
        #expect(response.results["GB"] != nil)
        #expect(response.results["FR"] == nil, "a region with no offers is simply absent")

        let us = try #require(response.results["US"]).streamingProviders()
        #expect(us.allSatisfy { $0.name != "Amazon Prime Video" })
    }

    @Test("a title that streams nowhere decodes to an empty result, not an error")
    func providerEmpty() throws {
        let response = try Self.decode(TMDBWatchProvidersResponse.self, from: TMDBFixtures.watchProvidersEmpty)
        #expect(response.results.isEmpty)
    }

    // MARK: - Dates

    @Test("release dates parse to the published day")
    func dateParsing() throws {
        let date = try #require(ReleaseDate.parse("2024-02-27"))

        let components = ReleaseDate.calendar.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2024)
        #expect(components.month == 2)
        #expect(components.day == 27)
    }

    @Test("missing dates are nil", arguments: [nil, "", "not-a-date", "2024"])
    func missingDates(_ raw: String?) {
        #expect(ReleaseDate.parse(raw) == nil)
    }

    // MARK: - Image URLs

    @Test("image URLs build against the TMDB CDN, and nil paths stay nil")
    func imageURLs() {
        #expect(TMDBService.posterURL(path: nil) == nil)
        #expect(TMDBService.posterURL(path: "") == nil, "an empty path must not build a 404 URL")

        #expect(
            TMDBService.posterURL(path: "/abc.jpg", size: .medium)?.absoluteString
                == "https://image.tmdb.org/t/p/w342/abc.jpg"
        )
        #expect(
            TMDBService.logoURL(path: "/logo.jpg", size: .small)?.absoluteString
                == "https://image.tmdb.org/t/p/w92/logo.jpg"
        )
    }

    // MARK: - Helpers

    /// Midnight UTC on the given day — what `ReleaseDate.parse` should produce.
    private func expectedDate(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        ReleaseDate.calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
