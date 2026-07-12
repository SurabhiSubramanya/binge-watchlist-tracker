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

    var watchStatus: WatchStatus
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
    /// True when the title comes out on a day after today — drives the "Upcoming"
    /// tag and whether a release reminder is offered.
    ///
    /// Goes through ``ReleaseDate`` rather than comparing to `.now`: release dates
    /// are floating calendar dates, so this has to be a day-to-day comparison.
    var isUpcoming: Bool {
        guard let releaseDate else { return false }
        return ReleaseDate.isUpcoming(releaseDate)
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
