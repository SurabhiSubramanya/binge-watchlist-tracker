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
                            .background(Color.accentColor, in: Capsule())
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

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(year ?? "—")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // Loaded and failed — a retry won't help, so show the
                    // fallback rather than an endless spinner.
                    fallback
                case .empty:
                    placeholder
                @unknown default:
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
