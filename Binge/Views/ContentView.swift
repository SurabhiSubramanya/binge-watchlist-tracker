import SwiftData
import SwiftUI

/// Root of the app — the three top-level destinations.
struct ContentView: View {
    @Environment(AppSettings.self) private var settings

    @State private var selection: Tab = .library

    enum Tab: Hashable {
        case library, search, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            // Library and Search are placeholders until Subtasks 6 and 7.
            PlaceholderTab(
                title: "Library",
                systemImage: "square.stack.3d.up.fill",
                message: "Titles you want to watch — and the ones you already have — will live here."
            )
            .tabItem { Label("Library", systemImage: "square.stack") }
            .tag(Tab.library)

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
