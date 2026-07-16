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
            // Fade only the lower part into the ground — enough to seat the poster
            // and title without a hard edge, while leaving the top half of the
            // artwork at its true colours. An even top-to-bottom fade (what this
            // was) dimmed the whole backdrop into a murky vignette that hid the
            // real image below the midline.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.5),
                    .init(color: .bingeGround.opacity(0.85), location: 0.86),
                    .init(color: .bingeGround, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var empty: some View {
        Rectangle().fill(.white.opacity(0.05))
    }
}
