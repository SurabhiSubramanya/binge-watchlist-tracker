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
            ContentView()
                .preferredColorScheme(.dark)
                .environment(settings)
        }
        .modelContainer(container)
    }
}
