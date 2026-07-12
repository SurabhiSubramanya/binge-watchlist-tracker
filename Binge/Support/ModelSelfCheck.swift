#if DEBUG
import Foundation
import SwiftData

/// Temporary Subtask-2 verification harness.
///
/// Exercises the `MediaItem` model end-to-end against an in-memory SwiftData
/// store: register schema → insert → save → fetch back → validate. This proves
/// the enums and — the plan's flagged risk — the inline `[StreamingProvider]`
/// Codable array survive a persistence round-trip.
///
/// This whole file is removed once the real `ModelContainer` is wired up in
/// Subtask 5; it exists only to make Subtask 2 observably "tested".
enum ModelSelfCheck {
    @MainActor
    static func run() -> String {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: MediaItem.self, configurations: config)
            let context = container.mainContext

            let item = MediaItem(
                tmdbId: 693134,
                mediaType: .movie,
                title: "Dune: Part Two",
                overview: "Paul Atreides unites with the Fremen to wage war against House Harkonnen.",
                posterPath: "/poster.jpg",
                backdropPath: "/backdrop.jpg",
                releaseDate: DateComponents(calendar: .current, year: 2024, month: 3, day: 1).date,
                genres: ["Science Fiction", "Adventure"]
            )
            item.streamingProviders = [
                StreamingProvider(providerId: 1899, name: "Max", logoPath: "/max.jpg", offer: .stream, displayPriority: 0),
                StreamingProvider(providerId: 2, name: "Apple TV", logoPath: "/atv.jpg", offer: .rent, displayPriority: 1),
                StreamingProvider(providerId: 2, name: "Apple TV", logoPath: "/atv.jpg", offer: .buy, displayPriority: 1)
            ]
            item.providersRegion = "US"
            context.insert(item)
            try context.save()

            let fetched = try context.fetch(FetchDescriptor<MediaItem>())
            guard fetched.count == 1, let first = fetched.first else {
                return "✗ expected 1 item, got \(fetched.count)"
            }
            guard first.streamingProviders.count == 3 else {
                return "✗ providers lost in round-trip (\(first.streamingProviders.count)/3)"
            }
            guard first.mediaType == .movie, first.watchStatus == .wantToWatch else {
                return "✗ enum round-trip failed"
            }
            guard first.streamingOffers.count == 1, first.rentOrBuyOffers.count == 2 else {
                return "✗ offer grouping wrong"
            }
            guard first.uniqueKey == "movie-693134" else {
                return "✗ unique key wrong (\(first.uniqueKey))"
            }
            return "✓ model OK · 1 item · 3 providers · key \(first.uniqueKey)"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }
}
#endif
