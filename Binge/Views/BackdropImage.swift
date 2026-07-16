import SwiftUI

/// The header backdrop, shared by the detail screen and the search preview.
///
/// Shows the title's backdrop, falling back to its poster when TMDB has no
/// backdrop, and fades it into the ground so the poster laid over it doesn't
/// sit on a hard edge.
///
/// Loaded through ``RemoteImage`` rather than `AsyncImage` for the same reasons
/// `MediaPosterView` is (Fix 2): a bare `AsyncImage` never retries a dropped
/// fetch — leaving a permanently blank rectangle behind the header — and caches
/// nothing, so it re-fetches every time the screen opens. ``RemoteImage`` caches
/// and retries; a milder symptom than the grid's, but the same fix.
struct BackdropImage: View {
    let backdropPath: String?
    let posterPath: String?
    var height: CGFloat = 210

    private var url: URL? {
        TMDBService.backdropURL(path: backdropPath)
            ?? TMDBService.posterURL(path: posterPath, size: .large)
    }

    var body: some View {
        Group {
            if let url {
                RemoteImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .loading, .failure:
                        // No spinner for a header backdrop — it's decoration, not
                        // the point of the screen. A quiet fill both while it loads
                        // and if it never does.
                        empty
                    }
                }
            } else {
                empty
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            // Fade the artwork into the page so the poster below it doesn't sit
            // on a hard edge.
            LinearGradient(
                colors: [.clear, .bingeGround.opacity(0.7), .bingeGround],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var empty: some View {
        Rectangle().fill(.white.opacity(0.05))
    }
}
