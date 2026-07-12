import SwiftData
import SwiftUI

/// The library: what you want to watch, and what you already have.
///
/// Fetches everything with one `@Query` and does the filtering and sorting in
/// memory. A `#Predicate`/`SortDescriptor` per combination would mean rebuilding
/// the query on every control change, and this is a personal library — hundreds
/// of titles, not hundreds of thousands. Cheap, and it keeps the nil-release-date
/// ordering (below) expressible, which `SortDescriptor` makes awkward.
struct LibraryView: View {
    @Query private var items: [MediaItem]

    @State private var status: WatchStatus = .wantToWatch
    @State private var sort: SortOption = .dateAdded
    @State private var typeFilter: TypeFilter = .all

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bingeGround.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Status", selection: $status) {
                        ForEach(WatchStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar { toolbarMenu }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(visibleItems) { item in
                    NavigationLink(value: item) {
                        MediaPosterView(
                            title: item.title,
                            posterPath: item.posterPath,
                            mediaType: item.mediaType,
                            year: item.releaseYear,
                            badge: item.isUpcoming ? "Upcoming" : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        Spacer()

        if items.isEmpty {
            // Nothing at all — the user hasn't added anything yet.
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "film.stack")
            } description: {
                Text("Find something on the Search tab and add it to your library.")
            }
        } else if hasItemsInStatusButFilteredOut {
            // They do have titles here — the *filter* is hiding them. Say so,
            // rather than implying the list is empty.
            ContentUnavailableView {
                Label("No \(typeFilter.displayName.lowercased())", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("You have titles in \(status.displayName), but none match the current filter.")
            } actions: {
                Button("Show all") { typeFilter = .all }
            }
        } else {
            ContentUnavailableView {
                Label(status.emptyTitle, systemImage: status.emptyIcon)
            } description: {
                Text(status.emptyMessage)
            }
        }

        Spacer()
    }

    /// True when this list would have something in it if the type filter weren't on.
    private var hasItemsInStatusButFilteredOut: Bool {
        typeFilter != .all && items.contains { $0.watchStatus == status }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.displayName, systemImage: option.icon).tag(option)
                    }
                }

                Picker("Show", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { filter in
                        Label(filter.displayName, systemImage: filter.icon).tag(filter)
                    }
                }
            } label: {
                Label("Sort and filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            // A filled glyph is the standard hint that a filter is narrowing things.
            .symbolVariant(typeFilter == .all ? .none : .fill)
        }
    }

    // MARK: - Filtering and sorting

    private var visibleItems: [MediaItem] {
        items
            .filter { $0.watchStatus == status && typeFilter.matches($0.mediaType) }
            .sorted(by: sort.areInIncreasingOrder)
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded
        case releaseDate
        case title

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dateAdded: return "Recently added"
            case .releaseDate: return "Release date"
            case .title: return "Title"
            }
        }

        var icon: String {
            switch self {
            case .dateAdded: return "clock"
            case .releaseDate: return "calendar"
            case .title: return "textformat.abc"
            }
        }

        func areInIncreasingOrder(_ lhs: MediaItem, _ rhs: MediaItem) -> Bool {
            switch self {
            case .dateAdded:
                return lhs.dateAdded > rhs.dateAdded          // newest first

            case .releaseDate:
                // Newest first — but a title with no known date must not be
                // treated as 1970 and dumped at the top of an ascending sort or
                // the bottom of a descending one *by accident*. Unknown dates
                // sink deliberately, and tie-break by title so the order is stable.
                switch (lhs.releaseDate, rhs.releaseDate) {
                case let (left?, right?):
                    return left == right
                        ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                        : left > right
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

            case .title:
                // localizedStandard so "Episode 2" sorts before "Episode 10".
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    enum TypeFilter: String, CaseIterable, Identifiable {
        case all
        case movies
        case tv

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "All"
            case .movies: return "Movies"
            case .tv: return "TV"
            }
        }

        var icon: String {
            switch self {
            case .all: return "square.stack"
            case .movies: return "film"
            case .tv: return "tv"
            }
        }

        func matches(_ mediaType: MediaType) -> Bool {
            switch self {
            case .all: return true
            case .movies: return mediaType == .movie
            case .tv: return mediaType == .tv
            }
        }
    }
}

private extension WatchStatus {
    var emptyTitle: String {
        switch self {
        case .wantToWatch: return "Nothing to watch"
        case .watched: return "Nothing watched yet"
        }
    }

    var emptyIcon: String {
        switch self {
        case .wantToWatch: return "bookmark"
        case .watched: return "checkmark.circle"
        }
    }

    var emptyMessage: String {
        switch self {
        case .wantToWatch: return "Add something from Search and it'll show up here."
        case .watched: return "Titles you mark as watched will collect here."
        }
    }
}

#Preview {
    LibraryView()
        .modelContainer(SampleLibrary.previewContainer)
        .preferredColorScheme(.dark)
}
