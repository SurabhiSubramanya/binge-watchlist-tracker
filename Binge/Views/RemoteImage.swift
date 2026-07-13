import SwiftUI

/// Where a ``RemoteImage`` has got to.
///
/// Top-level rather than nested inside `RemoteImage`, for the same reason
/// `AsyncImagePhase` is: the content closure is what Swift infers `Content` *from*,
/// so a phase spelled `RemoteImage<Content>.Phase` would have to know the answer to
/// the question it's being asked.
enum RemoteImagePhase {
    case loading
    case success(Image)
    /// Fetched, retried, still nothing.
    case failure
}

/// Remote artwork, loaded through ``ArtworkLoader`` — so it's cached, and a fetch
/// that fails is tried again.
///
/// A stand-in for `AsyncImage` in the one place the difference matters: a cell in a
/// lazy grid, which SwiftUI builds, tears down and rebuilds as the user scrolls.
/// Two rules make that survivable, and both are things `AsyncImage` gets wrong here:
///
/// - **A cancelled load is not a failure.** When a cell scrolls off mid-fetch the
///   load is cancelled; that leaves the view in ``Phase/loading``, and `task(id:)`
///   starts it again if the cell comes back. `AsyncImage` counted this as `.failure`
///   and never tried again — a permanent hole in the grid.
/// - **A cache hit resolves before the first render**, in `init`, so a rebuilt cell
///   shows its poster in the frame it appears rather than flashing a spinner over
///   artwork already in memory.
struct RemoteImage<Content: View>: View {
    private let url: URL
    private let loader: ArtworkLoader
    private let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase

    init(
        url: URL,
        loader: ArtworkLoader = .shared,
        @ViewBuilder content: @escaping (RemoteImagePhase) -> Content
    ) {
        self.url = url
        self.loader = loader
        self.content = content
        _phase = State(
            initialValue: loader.cachedImage(for: url)
                .map { .success(Image(uiImage: $0)) } ?? .loading
        )
    }

    var body: some View {
        content(phase)
            // Keyed on the URL: a cell recycled onto different artwork reloads,
            // rather than keeping the picture that belonged to the last one.
            .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = loader.cachedImage(for: url) {
            phase = .success(Image(uiImage: cached))
            return
        }

        phase = .loading

        do {
            phase = .success(Image(uiImage: try await loader.image(for: url)))
        } catch is CancellationError {
            // The cell went away while we were fetching. Nothing failed — leave it
            // loading, and `task(id:)` will pick it up again if it comes back.
            // Calling this a failure is precisely the bug this view exists to fix.
        } catch {
            phase = .failure
        }
    }
}
