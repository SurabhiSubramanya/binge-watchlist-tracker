import UIKit

/// Fetches remote artwork, caches it, and retries a fetch that fails.
///
/// The poster grid used to hand its URLs straight to `AsyncImage`, which has two
/// properties a scrolling grid can't live with:
///
/// - **A failed load is final.** `AsyncImage` reports `.failure` and stops there.
///   One dropped connection therefore left a permanent placeholder in a cell whose
///   artwork was perfectly fine — which is how the *same URL* could come up blank
///   in the Library and load on the detail screen a second later.
/// - **It has no cache.** Every time a lazy cell was rebuilt the image was fetched
///   again, so scrolling generated a fresh burst of requests, and every one of them
///   was a new chance to draw the short straw above.
///
/// So this: decoded images kept in memory, bytes kept on disk, and a transient
/// failure tried again instead of being taken as the final word.
final class ArtworkLoader: Sendable {
    static let shared = ArtworkLoader()

    private let session: URLSession
    private let cache: ImageCache
    /// Total tries, not retries — 3 means one attempt and two more after it.
    private let attempts: Int
    /// Waited before the second attempt, then doubled for each one after.
    private let retryDelay: Duration

    init(
        session: URLSession = .artwork,
        cache: ImageCache = .shared,
        attempts: Int = 3,
        retryDelay: Duration = .milliseconds(400)
    ) {
        self.session = session
        self.cache = cache
        self.attempts = attempts
        self.retryDelay = retryDelay
    }

    /// Already-decoded artwork, if it's in memory. Synchronous by design: it lets a
    /// recycled grid cell put its picture up in the same frame it's built, instead
    /// of flashing a spinner over an image the app is already holding.
    func cachedImage(for url: URL) -> UIImage? {
        cache[url]
    }

    /// Artwork for `url`, retrying transient failures.
    ///
    /// Throws `CancellationError` when the cell that wanted it went away mid-flight.
    /// **Callers must not render that as a failure** — nothing went wrong, the
    /// question just stopped being asked.
    func image(for url: URL) async throws -> UIImage {
        if let cached = cache[url] { return cached }

        var lastError: any Error = ArtworkError.undecodable

        for attempt in 0..<attempts {
            if attempt > 0 {
                // Back off, and grow the gap. A grid full of cells that all failed
                // on the same blip and all retry in the same millisecond is how you
                // turn a blip into an outage.
                try await Task.sleep(for: retryDelay * (1 << (attempt - 1)))
            }
            try Task.checkCancellation()

            do {
                return try await fetch(url)
            } catch let error as ArtworkError where !error.isWorthRetrying {
                // TMDB genuinely doesn't have this artwork, or what it sent isn't an
                // image. Asking again more slowly won't change either answer.
                throw error
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func fetch(_ url: URL) async throws -> UIImage {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArtworkError.http(status: http.statusCode)
        }
        guard let image = UIImage(data: data) else { throw ArtworkError.undecodable }

        cache[url] = image
        return image
    }
}

// MARK: - Errors

enum ArtworkError: Error, Equatable {
    case http(status: Int)
    case undecodable

    /// Whether trying again could plausibly land differently. A 5xx or a throttle,
    /// yes — those are the CDN having a moment. A 404 is TMDB telling us the artwork
    /// isn't there, and no amount of asking will conjure it up.
    var isWorthRetrying: Bool {
        switch self {
        case .http(let status): return status == 429 || status >= 500
        case .undecodable: return false
        }
    }
}

// MARK: - Cache

/// Decoded artwork, held in memory.
///
/// `NSCache` rather than a dictionary specifically so iOS can evict posters when it
/// needs the memory, instead of killing Binge for hoarding them. It's also
/// thread-safe, which is what makes the `@unchecked Sendable` below honest rather
/// than a promise.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let images = NSCache<NSURL, UIImage>()

    /// The default holds roughly a few hundred `w342` posters — comfortably more
    /// than a personal library, and a ceiling `NSCache` will lower for us anyway if
    /// the system wants the room back.
    init(limitBytes: Int = 64 * 1024 * 1024) {
        images.totalCostLimit = limitBytes
    }

    subscript(url: URL) -> UIImage? {
        get { images.object(forKey: url as NSURL) }
        set {
            guard let newValue else {
                images.removeObject(forKey: url as NSURL)
                return
            }
            images.setObject(newValue, forKey: url as NSURL, cost: newValue.decodedByteCount)
        }
    }
}

private extension UIImage {
    /// What this actually costs to hold: decoded pixels, not the compressed bytes it
    /// arrived as. Weighing it by the latter would let the cache hold several times
    /// the memory it thinks it does.
    var decodedByteCount: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

// MARK: - Transport

extension URLSession {
    /// Artwork gets its **own** session, with its own HTTP cache.
    ///
    /// `URLSession.shared` — which ``TMDBService`` uses — is deliberately left alone:
    /// giving *it* a cache would also cache TMDB's API responses, and the detail
    /// screen's Refresh button must never be answered out of a cache we introduced.
    /// Availability going stale is the one thing that button exists to prevent.
    static let artwork: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        // A TMDB image path is effectively immutable — new artwork is published at a
        // new path — so a poster we already have never needs revalidating. This is
        // what makes a relaunch paint the library instantly instead of re-downloading
        // it, and what lets it paint at all with no signal.
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
}
