import Foundation

/// Everything Binge knows how to ask TMDB.
///
/// Plain `URLSession` + `async`/`await` + `Codable`, no third-party dependencies —
/// it's three endpoints. Auth is TMDB's **v4 Read Access Token** as a Bearer
/// header, read from ``AppSettings`` on *every* call, so replacing the token in
/// Settings takes effect immediately with no cache to invalidate.
@MainActor
final class TMDBService {
    private let settings: AppSettings
    private let session: URLSession

    private static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    /// `nonisolated` so the image-URL helpers below can reach it.
    nonisolated private static let imageBaseURL = "https://image.tmdb.org/t/p"

    /// The decoder every DTO is decoded through.
    ///
    /// `nonisolated` because it has nothing to do with the main actor — the class
    /// is `@MainActor` only so instance methods can read `AppSettings`, and that
    /// isolation would otherwise leak onto the statics.
    ///
    /// Not private: `convertFromSnakeCase` is load-bearing for every DTO, so the
    /// tests decode through *this* rather than a lookalike that could quietly
    /// drift out of sync with it. Freshly built each time rather than shared —
    /// `JSONDecoder` isn't `Sendable`, and one allocation is nothing next to the
    /// HTTP round trip it accompanies.
    nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    // MARK: - Endpoints

    /// Search movies *and* TV in one call.
    ///
    /// `person` hits — and any media type TMDB adds later — are dropped rather
    /// than failing the page, so a director showing up in the results for
    /// "dune" can't break the search.
    func searchMulti(query: String) async throws -> [TMDBSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response: TMDBSearchResponse = try await get(
            path: "search/multi",
            query: [
                URLQueryItem(name: "query", value: trimmed),
                URLQueryItem(name: "include_adult", value: "false"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        return response.results.compactMap { $0.normalized() }
    }

    /// The fuller record for one title. TMDB doesn't echo the media type back,
    /// so it's threaded through from the caller.
    func details(for tmdbId: Int, mediaType: MediaType) async throws -> TMDBTitleDetails {
        let response: TMDBDetailsResponse = try await get(path: "\(mediaType.tmdbPath)/\(tmdbId)")
        return response.normalized(mediaType: mediaType)
    }

    /// Where a title streams **in one region**.
    ///
    /// TMDB returns every region it knows about in a single payload; we keep
    /// only the one asked for. An empty array is a perfectly good answer — lots
    /// of titles stream nowhere in a given country — so callers should render
    /// "not available to stream" rather than treating it as an error.
    func watchProviders(
        for tmdbId: Int,
        mediaType: MediaType,
        region: String
    ) async throws -> [StreamingProvider] {
        let response: TMDBWatchProvidersResponse = try await get(
            path: "\(mediaType.tmdbPath)/\(tmdbId)/watch/providers"
        )
        guard let offers = response.results[region.uppercased()] else { return [] }
        return offers.streamingProviders()
    }

    // MARK: - Image URLs

    // All `nonisolated`: these are pure string builders with no actor state, and
    // `AsyncImage` needs to call them from wherever it happens to be.

    nonisolated static func posterURL(path: String?, size: PosterSize = .medium) -> URL? {
        imageURL(path: path, size: size.rawValue)
    }

    nonisolated static func backdropURL(path: String?, size: BackdropSize = .medium) -> URL? {
        imageURL(path: path, size: size.rawValue)
    }

    nonisolated static func logoURL(path: String?, size: LogoSize = .small) -> URL? {
        imageURL(path: path, size: size.rawValue)
    }

    /// TMDB image paths already carry their leading slash.
    nonisolated private static func imageURL(path: String?, size: String) -> URL? {
        guard let path = path.nonEmpty else { return nil }
        return URL(string: "\(imageBaseURL)/\(size)\(path)")
    }

    // MARK: - Transport

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        // The one check that has to come first: without a token every request
        // is a guaranteed 401, so fail with something the UI can act on.
        guard let token = settings.bearerToken else { throw TMDBError.missingToken }

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw TMDBError.invalidRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw TMDBError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TMDBError.invalidRequest }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw TMDBError.unauthorized
        case 404:
            throw TMDBError.notFound
        case 429:
            throw TMDBError.rateLimited
        default:
            throw TMDBError.server(status: http.statusCode)
        }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw TMDBError.decoding(error)
        }
    }
}

// MARK: - Image sizes

extension TMDBService {
    /// TMDB's fixed image widths. Not free-form — these are the buckets the CDN
    /// actually serves.
    enum PosterSize: String {
        case small = "w185"
        case medium = "w342"
        case large = "w500"
        case original
    }

    enum BackdropSize: String {
        case medium = "w780"
        case large = "w1280"
        case original
    }

    enum LogoSize: String {
        case small = "w92"
        case medium = "w154"
    }
}

// MARK: - Errors

/// Everything that can go wrong talking to TMDB, split by what the *user* can do
/// about it — the plan's requirement is that a missing or bad token produces a
/// clear "add your token" state rather than a hang or a crash.
enum TMDBError: LocalizedError {
    /// No token in the Keychain yet — the first-run state.
    case missingToken
    /// TMDB rejected the token (401). Usually the v3 API key pasted by mistake.
    case unauthorized
    case notFound
    case rateLimited
    case server(status: Int)
    case network(URLError)
    case decoding(DecodingError)
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your TMDB token in Settings to search titles and see where they stream."
        case .unauthorized:
            return "TMDB rejected that token. Check it in Settings — Binge needs the long Read Access Token (v4), not the short API key (v3)."
        case .notFound:
            return "TMDB doesn't have that title."
        case .rateLimited:
            return "Too many requests to TMDB just now. Give it a moment."
        case .server(let status):
            return "TMDB is having trouble (HTTP \(status)). Try again shortly."
        case .network:
            return "Couldn't reach TMDB. Check your connection."
        case .decoding:
            return "TMDB sent back something Binge didn't understand."
        case .invalidRequest:
            return "Binge built a bad request. That's a bug."
        }
    }

    /// True when the fix is "go to Settings and sort your token out" — lets the
    /// UI offer that shortcut instead of a generic retry.
    var isTokenProblem: Bool {
        switch self {
        case .missingToken, .unauthorized: return true
        default: return false
        }
    }
}
