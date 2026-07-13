import SwiftData
import SwiftUI

@main
struct BingeApp: App {
    /// App-wide configuration (TMDB token + streaming region). Built once here
    /// and handed to the whole view tree through the environment.
    @State private var settings = AppSettings()

    /// The on-device SwiftData store. Local-only by design: free Apple ID
    /// signing can't ship the CloudKit entitlement, so there's no sync.
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: MediaItem.self)
        } catch {
            // Every screen is driven by `@Query` against this store, so a store
            // we can't open isn't something the app can limp along without —
            // failing loudly beats silently showing an empty library forever.
            fatalError("Couldn't open the Binge data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(settings)
        }
        .modelContainer(container)
    }
}

/// The app, under the launch curtain.
///
/// `ContentView` is built and running underneath from the very first frame — its
/// `task` (reconciling reminders, deciding which tab to open on) does its work while
/// the curtain is still up, so lifting it reveals a screen that's already settled
/// rather than one that's still assembling itself.
private struct RootView: View {
    @State private var isLaunching = true

    var body: some View {
        ZStack {
            ContentView()

            if isLaunching {
                LaunchCurtain { isLaunching = false }
                    // The curtain fades; the app is already behind it, so this reads
                    // as a cross-fade without having to animate both halves.
                    .transition(.opacity)
            }
        }
    }
}
