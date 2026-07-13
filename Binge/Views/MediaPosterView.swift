import SwiftUI

/// A poster cell — artwork, title, and year.
///
/// Shared by the Library grid (Subtask 6) and Search results (Subtask 7), which
/// is why it takes plain values rather than a `MediaItem`: search results aren't
/// in the store yet.
struct MediaPosterView: View {
    let title: String
    let posterPath: String?
    let mediaType: MediaType
    var year: String?
    var badge: String?
    /// Gold reads as "coming soon", green as "you already have this" — Search
    /// shows both kinds, and they shouldn't look alike.
    var badgeTint: Color = .accentColor
    /// The detail screen already prints the title in full beside the artwork —
    /// repeating it under the poster would just be saying it twice.
    var showsCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            poster
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(badgeTint, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(6)
                    }
                }
                .overlay {
                    // A hairline keeps dark posters from bleeding into the
                    // equally dark background.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }

            if showsCaption {
                // Always two lines tall, even for a one-line title. Otherwise a
                // short title makes a shorter cell, the grid row is as tall as
                // its tallest cell, and the short one gets centred in it — which
                // pushes its poster down out of line with its neighbours'.
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                Text(year ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        // The whole cell reads as one thing to VoiceOver, not four.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [title, year, mediaType.displayName, badge]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Artwork

    @ViewBuilder
    private var poster: some View {
        if let url = TMDBService.posterURL(path: posterPath) {
            // Not `AsyncImage`: it doesn't cache, and it treats a single failed
            // fetch as final. In a grid that builds and tears down cells as you
            // scroll, that lost posters at random — the cell gave up for good on
            // artwork that was fine, and the same URL then loaded on the detail
            // screen. `RemoteImage` caches and retries.
            RemoteImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .loading:
                    placeholder
                case .failure:
                    // Fetched, retried, still nothing. Now the fallback is the truth.
                    fallback
                }
            }
        } else {
            // TMDB simply has no artwork for this title.
            fallback
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay { ProgressView().tint(.secondary) }
    }

    /// No artwork — so the title has to carry the cell. Never show an empty box.
    private var fallback: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: mediaType == .movie ? "film" : "tv")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(8)
            }
    }
}

#Preview {
    ZStack {
        Color.bingeGround.ignoresSafeArea()

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14)], spacing: 18) {
            MediaPosterView(
                title: "Dune: Part Two",
                posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg",
                mediaType: .movie,
                year: "2024"
            )
            MediaPosterView(
                title: "A Title TMDB Has No Poster For",
                posterPath: nil,
                mediaType: .tv,
                year: "2026",
                badge: "Upcoming"
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
