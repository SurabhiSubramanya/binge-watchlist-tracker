import SwiftUI

/// How much you've actually got through: films and series, counted separately.
///
/// Pinned under the Library grid rather than scrolled with it — a total that scrolls
/// off the bottom is a total you have to go looking for, which rather defeats it.
///
/// Shown for **Watched** only. "How much have I got through" is a question about what
/// you've finished; the same number over Want to Watch would just be counting a
/// backlog, which is a different (and less welcome) fact.
struct LibraryFooter: View {
    let movies: Int
    let tv: Int

    var body: some View {
        VStack(spacing: 0) {
            // Separates the tally from the last row of posters without ruling a hard
            // line across the page.
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                stat(count: movies, noun: "Movie")

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 0.5, height: 30)

                stat(count: tv, noun: "TV Show")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.bingeGround)
        // One sentence, not four fragments read out in a row.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Watched: ^[\(movies) movie](inflect: true), ^[\(tv) TV show](inflect: true)")
    }

    private func stat(count: Int, noun: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.accentColor)

            // The number is styled separately above, so it can't carry the number
            // agreement with it — the label has to agree on its own, or a library
            // with one film in it reads "1 MOVIES".
            Text((count == 1 ? noun : "\(noun)s").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        Color.bingeGround.ignoresSafeArea()
        VStack {
            Spacer()
            LibraryFooter(movies: 12, tv: 5)
        }
    }
    .preferredColorScheme(.dark)
}
