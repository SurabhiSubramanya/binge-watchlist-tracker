import SwiftUI

/// Temporary launch screen for the project scaffold (Subtask 1).
/// Subtask 5 replaces this with the real tabbed navigation
/// (Library · Search · Settings).
struct ContentView: View {
    #if DEBUG
    @State private var selfCheck = "Running model self-check…"
    @State private var settingsCheck = "Running settings self-check…"
    #endif

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

                #if DEBUG
                // Temporary Subtask-2 / Subtask-3 indicators; both removed when
                // tabs and the real Settings screen land in Subtask 5.
                VStack(spacing: 6) {
                    selfCheckLine(selfCheck)
                    selfCheckLine(settingsCheck)
                }
                .padding(.top, 10)
                .padding(.horizontal, 24)
                #endif
            }
        }
        #if DEBUG
        .task {
            selfCheck = ModelSelfCheck.run()
            settingsCheck = SettingsSelfCheck.run()
        }
        #endif
    }

    #if DEBUG
    private func selfCheckLine(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .multilineTextAlignment(.center)
            .foregroundStyle(text.hasPrefix("✓") ? Color.green : Color.orange)
    }
    #endif
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
