import SwiftData
import SwiftUI

/// Root of the app — the three top-level destinations.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var selection: Tab = .library

    enum Tab: Hashable {
        case library, search, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            // Search is still a placeholder until Subtask 7.
            PlaceholderTab(
                title: "Search",
                systemImage: "magnifyingglass",
                message: "Search TMDB for a movie or show, then add it to your library."
            )
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                // A quiet dot on the tab while the app can't reach TMDB at all.
                .badge(settings.isConfigured ? 0 : 1)
                .tag(Tab.settings)
        }
        .tint(.accentColor)
        .task {
            #if DEBUG
            // Subtask-6 verification run: populate the Library so the grid can be
            // seen, and stay on it rather than bouncing to the token nudge.
            if SampleLibrary.isRequested {
                SampleLibrary.seed(into: modelContext)
                selection = .library
                return
            }
            #endif

            // First-launch nudge: with no token, every network feature is dead,
            // so open onto Settings rather than an empty Library the user has
            // no way to fill.
            if !settings.isConfigured {
                selection = .settings
            }
        }
    }
}

/// Stand-in for a tab that hasn't been built yet. Replaced by the real Library
/// (Subtask 6) and Search (Subtask 7) screens.
private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bingeGround.ignoresSafeArea()

                ContentUnavailableView {
                    Label(title, systemImage: systemImage)
                } description: {
                    Text(message)
                }
            }
            .navigationTitle(title)
        }
    }
}

#Preview("Configured") {
    ContentView()
        .environment(AppSettings.preview(token: "preview-token"))
        .preferredColorScheme(.dark)
}

#Preview("Needs token") {
    ContentView()
        .environment(AppSettings.preview())
        .preferredColorScheme(.dark)
}
