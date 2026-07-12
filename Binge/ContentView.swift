import SwiftUI

/// Temporary launch screen for the project scaffold (Subtask 1).
/// Subtask 5 replaces this with the real tabbed navigation
/// (Library · Search · Settings).
struct ContentView: View {
    var body: some View {
        ZStack {
            // App ground — the dark, cinematic base from the approved mockups (#0B0D13).
            Color(red: 11 / 255, green: 13 / 255, blue: 19 / 255)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "film.stack")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Binge")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)

                Text("Track what to watch — and where.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
