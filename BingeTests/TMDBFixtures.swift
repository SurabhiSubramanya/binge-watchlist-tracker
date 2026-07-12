import Foundation

/// Saved TMDB payloads, trimmed to the fields Binge decodes but otherwise shaped
/// exactly like the real thing — including the parts that are easy to get wrong:
/// a `person` row mixed into search results, `""` for a missing image path, a
/// provider that appears in two buckets at once, and a region we never asked for.
enum TMDBFixtures {

    /// `GET /3/search/multi?query=dune`
    ///
    /// Three rows on purpose: a movie (`title` + `release_date`), a TV series
    /// (`name` + `first_air_date`), and a person (neither) that must be dropped.
    /// The TV row carries `"backdrop_path": ""` — TMDB's other way of saying null.
    static let searchMulti = Data("""
    {
      "page": 1,
      "results": [
        {
          "id": 693134,
          "media_type": "movie",
          "title": "Dune: Part Two",
          "original_title": "Dune: Part Two",
          "overview": "Paul Atreides unites with the Fremen to wage war against House Harkonnen.",
          "poster_path": "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
          "backdrop_path": "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
          "release_date": "2024-02-27",
          "genre_ids": [878, 12],
          "adult": false,
          "popularity": 245.6,
          "vote_average": 8.2
        },
        {
          "id": 87739,
          "media_type": "tv",
          "name": "Dune: Prophecy",
          "original_name": "Dune: Prophecy",
          "overview": "Ten thousand years before the ascension of Paul Atreides.",
          "poster_path": "/9wgIcMhBAMwYd0qBpFqYhLPUeVQ.jpg",
          "backdrop_path": "",
          "first_air_date": "2024-11-17",
          "genre_ids": [10765, 18],
          "origin_country": ["US"],
          "vote_average": 7.5
        },
        {
          "id": 1190668,
          "media_type": "person",
          "name": "Denis Villeneuve",
          "known_for_department": "Directing",
          "profile_path": "/zdDx9Xs93UonQupIfDLVJoWlqzR.jpg",
          "adult": false,
          "popularity": 12.3
        }
      ],
      "total_pages": 1,
      "total_results": 3
    }
    """.utf8)

    /// `GET /3/movie/693134`
    static let movieDetails = Data("""
    {
      "id": 693134,
      "title": "Dune: Part Two",
      "overview": "Paul Atreides unites with the Fremen to wage war against House Harkonnen.",
      "poster_path": "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
      "backdrop_path": "/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
      "release_date": "2024-02-27",
      "runtime": 167,
      "genres": [
        { "id": 878, "name": "Science Fiction" },
        { "id": 12, "name": "Adventure" }
      ],
      "adult": false,
      "vote_average": 8.2
    }
    """.utf8)

    /// `GET /3/tv/87739` — note `name` and `first_air_date` instead of
    /// `title` / `release_date`, and no release date at all.
    static let tvDetails = Data("""
    {
      "id": 87739,
      "name": "Dune: Prophecy",
      "overview": "Ten thousand years before the ascension of Paul Atreides.",
      "poster_path": "/9wgIcMhBAMwYd0qBpFqYhLPUeVQ.jpg",
      "backdrop_path": null,
      "first_air_date": "",
      "genres": [
        { "id": 10765, "name": "Sci-Fi & Fantasy" }
      ],
      "vote_average": 7.5
    }
    """.utf8)

    /// `GET /3/movie/693134/watch/providers`
    ///
    /// Two traps, both real TMDB behaviour:
    /// - **Max is in both `flatrate` and `ads`** — collapsing both to `.stream`
    ///   would otherwise produce two entries with the same `StreamingProvider.id`.
    /// - **Apple TV is in both `rent` and `buy`** — those are genuinely different
    ///   offers and *must both survive*.
    ///
    /// It also carries a `GB` region we never ask for, to prove region filtering.
    static let watchProviders = Data("""
    {
      "id": 693134,
      "results": {
        "US": {
          "link": "https://www.themoviedb.org/movie/693134/watch?locale=US",
          "flatrate": [
            { "provider_id": 1899, "provider_name": "Max", "logo_path": "/nmU0UMDJB3dRRQSTUqawzF2Od1a.jpg", "display_priority": 3 }
          ],
          "ads": [
            { "provider_id": 1899, "provider_name": "Max", "logo_path": "/nmU0UMDJB3dRRQSTUqawzF2Od1a.jpg", "display_priority": 9 }
          ],
          "rent": [
            { "provider_id": 2, "provider_name": "Apple TV", "logo_path": "/9ghgSC0MA082EL6HLCW3GalykFD.jpg", "display_priority": 5 }
          ],
          "buy": [
            { "provider_id": 2, "provider_name": "Apple TV", "logo_path": "/9ghgSC0MA082EL6HLCW3GalykFD.jpg", "display_priority": 5 }
          ]
        },
        "GB": {
          "link": "https://www.themoviedb.org/movie/693134/watch?locale=GB",
          "flatrate": [
            { "provider_id": 9, "provider_name": "Amazon Prime Video", "logo_path": "/dQeAar5H991VYporEjUspolDarG.jpg", "display_priority": 2 }
          ]
        }
      }
    }
    """.utf8)

    /// A region with nothing on offer at all — TMDB simply omits the key.
    static let watchProvidersEmpty = Data("""
    { "id": 111, "results": {} }
    """.utf8)
}
