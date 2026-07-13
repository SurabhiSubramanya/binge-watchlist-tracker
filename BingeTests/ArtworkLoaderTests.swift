import Foundation
import Testing
import UIKit
@testable import Binge

/// The Library grid used to lose posters at random. `AsyncImage` takes one failed
/// fetch as final, so a single dropped connection left a permanent placeholder in a
/// cell whose artwork was perfectly fine — and the very same URL would then load on
/// the detail screen, which is what made it look like a data problem when it never
/// was one.
///
/// ``ArtworkLoader`` is the fix, and these tests pin the two properties that make it
/// one: **it retries**, and **it caches**. Plus the two things it must *not* do —
/// retry a 404 forever, or mistake a cancelled cell for a broken image.
///
/// Serialized: ``StubTransport`` scripts its answers in shared static state, and
/// Swift Testing would otherwise run these in parallel and let them read each
/// other's mail.
@Suite("Artwork loading", .serialized)
struct ArtworkLoaderTests {

    private let url = URL(string: "https://image.tmdb.org/t/p/w342/poster.jpg")!

    // MARK: - Retrying

    /// **The bug.** One blip used to cost a poster for as long as the cell lived.
    @Test("a poster that fails once still loads")
    func retriesAfterATransientFailure() async throws {
        StubTransport.script([
            .failure(URLError(.networkConnectionLost)),
            .success(.image)
        ])

        let image = try await loader().image(for: url)

        #expect(image.size != .zero)
        #expect(StubTransport.requestCount == 2, "should have tried again after the dropped connection")
    }

    @Test("a poster survives everything but the last attempt")
    func retriesUpToTheLimit() async throws {
        StubTransport.script([
            .failure(URLError(.timedOut)),
            .failure(URLError(.networkConnectionLost)),
            .success(.image)
        ])

        _ = try await loader(attempts: 3).image(for: url)

        #expect(StubTransport.requestCount == 3)
    }

    @Test("a poster that never loads gives up rather than hanging")
    func givesUpAfterTheLastAttempt() async {
        StubTransport.script([.failure(URLError(.notConnectedToInternet))])

        await #expect(throws: (any Error).self) {
            try await loader(attempts: 3).image(for: url)
        }
        #expect(StubTransport.requestCount == 3, "three attempts, then the fallback — not an endless spinner")
    }

    /// A 5xx is the CDN having a moment, so it's worth asking again.
    @Test("a server error is retried")
    func retriesServerErrors() async throws {
        StubTransport.script([.success(.status(503)), .success(.image)])

        _ = try await loader().image(for: url)

        #expect(StubTransport.requestCount == 2)
    }

    /// A 404 is TMDB saying the artwork isn't there. Asking again more slowly won't
    /// change its mind, and the cell should get to its fallback promptly.
    @Test("artwork TMDB doesn't have is not retried")
    func doesNotRetryMissingArtwork() async {
        StubTransport.script([.success(.status(404))])

        await #expect(throws: ArtworkError.http(status: 404)) {
            try await loader().image(for: url)
        }
        #expect(StubTransport.requestCount == 1, "a 404 is a real answer, not a blip")
    }

    // MARK: - Caching

    @Test("a poster is fetched once, then served from memory")
    func cachesDecodedImages() async throws {
        StubTransport.script([.success(.image)])
        let loader = loader()

        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)

        #expect(StubTransport.requestCount == 1, "scrolling back to a cell must not re-download it")
        #expect(loader.cachedImage(for: url) != nil, "a rebuilt cell needs its poster without waiting")
    }

    /// Nothing is cached until it's actually in hand — otherwise a failed fetch would
    /// poison the cell for the rest of the session.
    @Test("a failed fetch caches nothing")
    func cachesNothingOnFailure() async {
        StubTransport.script([.failure(URLError(.timedOut))])
        let loader = loader(attempts: 1)

        _ = try? await loader.image(for: url)

        #expect(loader.cachedImage(for: url) == nil)
    }

    // MARK: - Cancellation

    /// A cell scrolling away mid-fetch must surface as a *cancellation*, so
    /// ``RemoteImage`` can leave the cell loading and try again when it returns —
    /// rather than burning it to the permanent failure state, which is the whole
    /// original bug.
    @Test("a cancelled load reports cancellation, not failure")
    func cancellationIsNotFailure() async throws {
        StubTransport.script([.failure(URLError(.cancelled))])

        await #expect(throws: CancellationError.self) {
            try await loader(attempts: 1).image(for: url)
        }
    }

    // MARK: - Harness

    private func loader(attempts: Int = 3) -> ArtworkLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubTransport.self]
        config.urlCache = nil

        return ArtworkLoader(
            session: URLSession(configuration: config),
            cache: ImageCache(),            // fresh per test — no bleed between them
            attempts: attempts,
            retryDelay: .milliseconds(1)    // these tests pin the retry, not the backoff
        )
    }
}

// MARK: - Stubbed transport

/// A scripted stand-in for the network. `URLProtocol` is the seam `URLSession` gives
/// you, and the session instantiates it on its own queue — hence the lock around the
/// script.
final class StubTransport: URLProtocol {

    /// One scripted answer. `.image` is real PNG bytes, because the loader decodes
    /// what it's given and a stub of `Data()` would fail for the wrong reason.
    enum Answer {
        case image
        case status(Int)

        var statusCode: Int {
            switch self {
            case .image: return 200
            case .status(let code): return code
            }
        }

        var body: Data {
            switch self {
            case .image: return .onePixelPNG
            case .status: return Data()
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [Result<Answer, URLError>] = []
    nonisolated(unsafe) private static var count = 0

    /// The answers to give, in order. The last one repeats once the script runs out,
    /// so "always times out" is just a one-entry script.
    static func script(_ answers: [Result<Answer, URLError>]) {
        lock.withLock {
            self.answers = answers
            count = 0
        }
    }

    static var requestCount: Int {
        lock.withLock { count }
    }

    private static func next() -> Result<Answer, URLError>? {
        lock.withLock {
            count += 1
            return answers.count > 1 ? answers.removeFirst() : answers.first
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch Self.next() {
        case .success(let answer):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: answer.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)

        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }
}

private extension Data {
    /// The smallest thing `UIImage` will accept as a real picture.
    static let onePixelPNG: Data = UIGraphicsImageRenderer(
        size: CGSize(width: 1, height: 1)
    ).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
