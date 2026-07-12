import Foundation

// MARK: - What the app actually works with
//
// The rest of Binge never sees TMDB's wire format. These normalized types are
// the service's output; the `Decodable` DTOs further down exist only to survive
// contact with the JSON and are mapped straight into these.

/// One search hit — enough to draw a poster cell, and enough to build a
/// `MediaItem` from if the user adds it.
struct TMDBSearchResult: Identifiable, Hashable {
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: Date?

    /// Deliberately the same composite key `MediaItem` dedups on, so the Search
    /// screen can tell at a glance what's already in the library.
    var id: String { MediaItem.makeUniqueKey(tmdbId: tmdbId, mediaType: mediaType) }
}

/// The fuller record behind the detail screen.
struct TMDBTitleDetails: Hashable {
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: Date?
    let genres: [String]
}

// MARK: - Wire format

/// TMDB's `search/multi` payload.
struct TMDBSearchResponse: Decodable {
    let page: Int
    let results: [TMDBSearchRow]
    let totalPages: Int
    let totalResults: Int
}

/// A single `search/multi` row.
///
/// `search/multi` is heterogeneous: movies carry `title` + `release_date`, TV
/// carries `name` + `first_air_date`, and people carry neither. So every field
/// here is optional — a person row (or some media type TMDB adds next year)
/// must not blow up the decode of the whole page. Rows are only *interpreted*
/// once `mediaType` says what they are; see `normalized()`.
struct TMDBSearchRow: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
}

/// `movie/{id}` and `tv/{id}` — same shape modulo the title/date field names.
struct TMDBDetailsResponse: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let genres: [Genre]?

    struct Genre: Decodable {
        let id: Int
        let name: String
    }
}

/// `…/watch/providers` — a map of region code → what's on offer there.
struct TMDBWatchProvidersResponse: Decodable {
    let id: Int
    let results: [String: RegionOffers]

    struct RegionOffers: Decodable {
        let link: String?
        let flatrate: [Provider]?
        let free: [Provider]?
        let ads: [Provider]?
        let rent: [Provider]?
        let buy: [Provider]?
    }

    struct Provider: Decodable {
        let providerId: Int
        let providerName: String
        let logoPath: String?
        let displayPriority: Int?
    }
}

// MARK: - Wire → app

extension TMDBSearchRow {
    /// `nil` for anything Binge doesn't track — `person` rows, rows with no
    /// usable title, and any media type TMDB invents later. Callers
    /// `compactMap` this, which is what makes an unknown row a skip rather than
    /// a failed page.
    func normalized() -> TMDBSearchResult? {
        guard let type = MediaType(tmdbMediaType: mediaType) else { return nil }

        // Movies put it in `title`, TV puts it in `name`.
        let resolvedTitle = (type == .movie ? title : name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !resolvedTitle.isEmpty else { return nil }

        return TMDBSearchResult(
            tmdbId: id,
            mediaType: type,
            title: resolvedTitle,
            overview: overview ?? "",
            posterPath: posterPath.nonEmpty,
            backdropPath: backdropPath.nonEmpty,
            releaseDate: TMDBDate.parse(type == .movie ? releaseDate : firstAirDate)
        )
    }
}

extension TMDBDetailsResponse {
    /// The endpoint already told us the media type — TMDB doesn't echo it back
    /// on the details payload, so the caller passes it through.
    func normalized(mediaType: MediaType) -> TMDBTitleDetails {
        let resolvedTitle = (mediaType == .movie ? title : name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return TMDBTitleDetails(
            tmdbId: id,
            mediaType: mediaType,
            title: resolvedTitle,
            overview: overview ?? "",
            posterPath: posterPath.nonEmpty,
            backdropPath: backdropPath.nonEmpty,
            releaseDate: TMDBDate.parse(mediaType == .movie ? releaseDate : firstAirDate),
            genres: (genres ?? []).map(\.name)
        )
    }
}

extension TMDBWatchProvidersResponse.RegionOffers {
    /// Flattens TMDB's five buckets into the three offers the app models.
    ///
    /// `flatrate`, `free`, and `ads` all collapse to `.stream`: from the user's
    /// side they all mean "you can watch this here without paying per title".
    ///
    /// That collapse can surface the same provider twice — a service often sits
    /// in both `flatrate` and `ads` — and `StreamingProvider.id` is keyed on
    /// provider + offer, so the duplicates would collide as SwiftUI `ForEach`
    /// ids. Dedup keeps the first occurrence, and the buckets are ordered so
    /// that means the best one (a real subscription beats an ad-supported tier).
    /// A provider legitimately appearing as both `.rent` and `.buy` survives as
    /// two entries, because those are genuinely different offers.
    func streamingProviders() -> [StreamingProvider] {
        let buckets: [(StreamingProvider.Offer, [TMDBWatchProvidersResponse.Provider]?)] = [
            (.stream, flatrate),
            (.stream, free),
            (.stream, ads),
            (.rent, rent),
            (.buy, buy)
        ]

        var seen = Set<String>()
        var providers: [StreamingProvider] = []

        for (offer, bucket) in buckets {
            for provider in bucket ?? [] {
                let mapped = StreamingProvider(
                    providerId: provider.providerId,
                    name: provider.providerName,
                    logoPath: provider.logoPath.nonEmpty,
                    offer: offer,
                    // TMDB omits priority sometimes; sink those to the bottom.
                    displayPriority: provider.displayPriority ?? .max
                )
                guard seen.insert(mapped.id).inserted else { continue }
                providers.append(mapped)
            }
        }

        return providers.sorted { $0.displayPriority < $1.displayPriority }
    }
}

extension MediaType {
    /// TMDB's `media_type` string → ours. `nil` for `person` and anything new.
    init?(tmdbMediaType: String?) {
        switch tmdbMediaType {
        case "movie": self = .movie
        case "tv": self = .tv
        default: return nil
        }
    }

    /// The path segment TMDB uses for this type: `/movie/…` or `/tv/…`.
    var tmdbPath: String {
        switch self {
        case .movie: return "movie"
        case .tv: return "tv"
        }
    }
}

// MARK: - Dates

/// TMDB sends plain calendar dates (`"2024-02-27"`) — no time, no zone — and
/// uses `""` as often as `null` for "unknown".
enum TMDBDate {
    /// Parsed as **local midnight**, via `Calendar.current`.
    ///
    /// The obvious alternative, UTC midnight, is a trap: anywhere west of
    /// Greenwich it reads back as the *previous day* once `Calendar.current`
    /// formats it — the classic release-date off-by-one. Local midnight keeps
    /// the calendar date the user sees identical to the one TMDB published, and
    /// agrees with `MediaItem.releaseYear` / `isUpcoming`, which already reason
    /// in `Calendar.current`.
    ///
    /// Built from `DateComponents` rather than a `DateFormatter` so it always
    /// picks up the *current* time zone and needs no shared mutable state.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }

        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }
}

extension Optional where Wrapped == String {
    /// TMDB uses `""` for "no image" about as often as it uses `null`, and an
    /// empty path would build a URL that 404s.
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
