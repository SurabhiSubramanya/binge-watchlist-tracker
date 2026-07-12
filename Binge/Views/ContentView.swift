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
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(Tab.library)

            SearchView()
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

#Preview("Configured") {
    ContentView()
        .environment(AppSettings.preview(token: "preview-token"))
        .modelContainer(SampleLibrary.previewContainer)
        .preferredColorScheme(.dark)
}

#Preview("Needs token") {
    ContentView()
        .environment(AppSettings.preview())
        .modelContainer(SampleLibrary.previewContainer)
        .preferredColorScheme(.dark)
}
