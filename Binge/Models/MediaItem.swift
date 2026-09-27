import Foundation
import SwiftData

// MARK: - Supporting value types

/// Whether a tracked title is a film or a series. Tracked as one whole unit —
/// Binge never drills into individual episodes.
enum MediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movie: return "Movie"
        case .tv: return "TV"
        }
    }
}

/// Which of the two libraries a title lives in.
enum WatchStatus: String, Codable, CaseIterable, Identifiable {
    case wantToWatch
    case watched

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wantToWatch: return "Want to Watch"
        case .watched: return "Watched"
        }
    }
}

/// A place a title can be watched, in a given region. Snapshotted from TMDB's
/// `watch/providers` data (which is powered by JustWatch) when a title is added
/// or refreshed. Stored inline on `MediaItem` as a Codable value.
struct StreamingProvider: Codable, Hashable, Identifiable {
    /// How the title is offered by this provider.
    enum Offer: String, Codable, CaseIterable {
        case stream   // included with a subscription (TMDB "flatrate")
        case rent
        case buy
    }

    var providerId: Int
    var name: String
    var logoPath: String?
    var offer: Offer
    /// TMDB's suggested ordering (lower = show first).
    var displayPriority: Int

    /// Unique per provider *and* offer, since one provider can appear as both
    /// e.g. rent and buy — keeps SwiftUI `ForEach` rows distinct.
    var id: String { "\(providerId)-\(offer.rawValue)" }
}

// MARK: - Model

/// A single tracked title (movie or series). This is the app's core record.
@Model
final class MediaItem {
    /// Composite key of `mediaType` + `tmdbId`, e.g. "movie-693134".
    /// TMDB ids are only unique *within* a media type, so uniqueness must be
    /// composite. `#Unique` (model-level composite) needs iOS 18; this derived
    /// `@Attribute(.unique)` string achieves the same on our iOS 17 target.
    @Attribute(.unique) var uniqueKey: String

    var tmdbId: Int
    var mediaType: MediaType
    var title: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: Date?
    var genres: [String]

    /// TV season data, snapshotted from TMDB on add/refresh (Option A). **All `nil`
    /// for movies.** `nextReleaseDate` is when the next episode/season airs — the
    /// date a series' Upcoming tag and release reminder key off, via
    /// ``effectiveReleaseDate``. `seriesStatus` stores the display label
    /// (`SeriesStatus.label`, e.g. "Returning" / "Ended"), not TMDB's raw string.
    ///
    /// All optional so adding them to the model is a *lightweight* SwiftData
    /// migration — the library already on the phone migrates with no mapping model.
    var numberOfSeasons: Int?
    var seriesStatus: String?
    var lastAirDate: Date?
    var nextReleaseDate: Date?
    var nextSeasonNumber: Int?

    var watchStatus: WatchStatus

    /// When this title last *entered its current list* — set on the initial add and
    /// bumped again whenever it moves between lists (see ``move(to:on:)``). It drives
    /// the "Recently added" sort, which is per-list, so moving a title to Watched is an
    /// "add" as far as ordering is concerned. Not shown anywhere; ordering is its only job.
    var dateAdded: Date

    /// Snapshot of where this title streams, and for which region it was fetched.
    var streamingProviders: [StreamingProvider]
    var providersRegion: String?
    var providersUpdatedAt: Date?

    /// Whether a local release-date reminder is currently scheduled for this title.
    var reminderScheduled: Bool

    init(
        tmdbId: Int,
        mediaType: MediaType,
        title: String,
        overview: String = "",
        posterPath: String? = nil,
        backdropPath: String? = nil,
        releaseDate: Date? = nil,
        genres: [String] = [],
        numberOfSeasons: Int? = nil,
        seriesStatus: String? = nil,
        lastAirDate: Date? = nil,
        nextReleaseDate: Date? = nil,
        nextSeasonNumber: Int? = nil,
        watchStatus: WatchStatus = .wantToWatch,
        dateAdded: Date = .now,
        streamingProviders: [StreamingProvider] = [],
        providersRegion: String? = nil,
        providersUpdatedAt: Date? = nil,
        reminderScheduled: Bool = false
    ) {
        self.uniqueKey = Self.makeUniqueKey(tmdbId: tmdbId, mediaType: mediaType)
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.genres = genres
        self.numberOfSeasons = numberOfSeasons
        self.seriesStatus = seriesStatus
        self.lastAirDate = lastAirDate
        self.nextReleaseDate = nextReleaseDate
        self.nextSeasonNumber = nextSeasonNumber
        self.watchStatus = watchStatus
        self.dateAdded = dateAdded
        self.streamingProviders = streamingProviders
        self.providersRegion = providersRegion
        self.providersUpdatedAt = providersUpdatedAt
        self.reminderScheduled = reminderScheduled
    }

    static func makeUniqueKey(tmdbId: Int, mediaType: MediaType) -> String {
        "\(mediaType.rawValue)-\(tmdbId)"
    }
}

// MARK: - Convenience

extension MediaItem {
    /// Move this title into `status`, treating the move as an "add" for the
    /// "Recently added" sort — so a title marked Watched lands at the top of the
    /// Watched list the same way a freshly-added one does, rather than keeping the
    /// spot it held by its original library-add date.
    ///
    /// A no-op move (already in `status`) leaves `dateAdded` untouched, so a stray
    /// toggle can't reshuffle the grid. `date` is injectable for tests.
    func move(to status: WatchStatus, on date: Date = .now) {
        guard watchStatus != status else { return }
        watchStatus = status
        dateAdded = date
    }

    /// Copy the TV season snapshot from a freshly fetched details record. Shared by
    /// the two places that fetch details — `SearchView.enrich` on add and
    /// `MediaDetailView.refresh` on open — so the mapping can't drift between them.
    ///
    /// A no-op in effect for movies: `TMDBTitleDetails` leaves every season field nil
    /// for a film, so this just writes nils back. `seriesStatus` is stored as the
    /// display label (`SeriesStatus.label`), which is all the UI needs.
    func applySeasonData(from details: TMDBTitleDetails) {
        numberOfSeasons = details.numberOfSeasons
        seriesStatus = details.seriesStatus?.label
        lastAirDate = details.lastAirDate
        nextReleaseDate = details.nextReleaseDate
        nextSeasonNumber = details.nextSeasonNumber
    }

    /// The date the "Upcoming" tag and the release reminder key off — the one place
    /// the movie/TV difference lives, so everything downstream stays media-agnostic.
    ///
    /// - **Movie:** its release date, unchanged.
    /// - **TV:** when the *next* episode/season airs (`nextReleaseDate`) if TMDB has
    ///   dated one, otherwise the premiere. That single fallback makes every case
    ///   fall out right: an ended show (`nextReleaseDate` nil, premiere in the past)
    ///   is correctly *not* upcoming and offers no reminder; a returning show with a
    ///   dated next season becomes upcoming and reminder-eligible; a not-yet-premiered
    ///   show still works off its premiere.
    var effectiveReleaseDate: Date? {
        switch mediaType {
        case .movie: return releaseDate
        case .tv: return nextReleaseDate ?? releaseDate
        }
    }

    /// True when the title's next release is on a day after today — drives the
    /// "Upcoming" tag and whether a release reminder is offered. For a series that's
    /// the next season/episode (see ``effectiveReleaseDate``), not the premiere.
    ///
    /// Goes through ``ReleaseDate`` rather than comparing to `.now`: release dates
    /// are floating calendar dates, so this has to be a day-to-day comparison.
    var isUpcoming: Bool {
        guard let effectiveReleaseDate else { return false }
        return ReleaseDate.isUpcoming(effectiveReleaseDate)
    }

    /// Four-digit release year for compact metadata lines, if known.
    var releaseYear: String? {
        guard let releaseDate else { return nil }
        return String(ReleaseDate.year(of: releaseDate))
    }

    /// The release date written out for display, in the user's locale's format —
    /// always the day TMDB published, whatever time zone the phone is in.
    var releaseDateText: String? {
        guard let releaseDate else { return nil }
        return ReleaseDate.formatted(releaseDate)
    }

    // MARK: - Detail meta line (Option A)

    /// The series status rebuilt from its stored label, for logic that needs the
    /// case rather than the display string (whether the run has concluded).
    var seriesStatusValue: SeriesStatus? {
        seriesStatus.map(SeriesStatus.init(label:))
    }

    /// The run timeline for the meta line: a closed span for a concluded series
    /// ("2008–2013", or a single year if it began and ended the same one),
    /// otherwise the premiere year ("2016") — the status word and the "Next" line
    /// carry the "still going" meaning, so an ongoing show isn't dressed up with a
    /// misleading end year. `nil` when no year is known at all.
    var runSpanText: String? {
        let premiereYear = releaseDate.map { ReleaseDate.year(of: $0) }
        let lastYear = lastAirDate.map { ReleaseDate.year(of: $0) }

        if seriesStatusValue?.isConcluded == true, let lastYear {
            guard let premiereYear, premiereYear != lastYear else { return "\(premiereYear ?? lastYear)" }
            return "\(premiereYear)–\(lastYear)"
        }
        return premiereYear.map(String.init)
    }

    /// "5 seasons" / "1 season", or `nil` when unknown. Pluralised by hand: the
    /// count sits inside one styled string, so SwiftUI's automatic grammar
    /// agreement can't reach it — the "1 MOVIES" trap from the watched-counts work.
    var seasonCountText: String? {
        guard let numberOfSeasons, numberOfSeasons > 0 else { return nil }
        return "\(numberOfSeasons) season\(numberOfSeasons == 1 ? "" : "s")"
    }

    /// "Next: Season 3, Jan 16, 2027" when a next episode/season is dated in the
    /// future; `nil` for an ended show, an undated next, or a date already past.
    /// A comma (not " · ") joins the season and date so it reads as one unit
    /// distinct from the meta line's own " · " separators.
    var nextReleaseText: String? {
        guard let nextReleaseDate, ReleaseDate.isUpcoming(nextReleaseDate) else { return nil }
        let date = ReleaseDate.formatted(nextReleaseDate, style: .medium)
        if let nextSeasonNumber {
            return "Next: Season \(nextSeasonNumber), \(date)"
        }
        return "Next: \(date)"
    }

    /// The subtitle under the title on the detail screen.
    ///
    /// A movie keeps the old "Movie · <date>" line. A series composes the season
    /// data Option A surfaces — run span · season count · status · next season —
    /// dropping any component TMDB doesn't have. A series with *no* season data or
    /// dates falls back to the movie-style line so it never reads as a bare "TV".
    var detailMetaLine: String {
        let unknownDateLine = [mediaType.displayName, releaseDateText ?? "Release date unknown"]
            .joined(separator: " · ")

        guard mediaType == .tv else { return unknownDateLine }

        let parts = [runSpanText, seasonCountText, seriesStatus, nextReleaseText].compactMap { $0 }
        guard !parts.isEmpty else { return unknownDateLine }
        return ([mediaType.displayName] + parts).joined(separator: " · ")
    }

    /// Providers grouped for display: what's included with a subscription vs.
    /// what must be rented/bought.
    var streamingOffers: [StreamingProvider] {
        streamingProviders
            .filter { $0.offer == .stream }
            .sorted { $0.displayPriority < $1.displayPriority }
    }

    var rentOrBuyOffers: [StreamingProvider] {
        streamingProviders
            .filter { $0.offer != .stream }
            .sorted { $0.displayPriority < $1.displayPriority }
    }
}
