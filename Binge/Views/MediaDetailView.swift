import SwiftData
import SwiftUI

/// One title, in full: artwork, when it's out, what it's about, where to stream
/// it — and everything you can do to it.
struct MediaDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: MediaItem

    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var notificationsDenied = false
    @State private var confirmingRemove = false

    var body: some View {
        ZStack {
            Color.bingeGround.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if !item.overview.isEmpty { overview }
                    streamingSection
                    actions
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing || !settings.isConfigured)
            }
        }
        // Best-effort refresh on open: providers go stale (and the region may have
        // changed since this was added), so re-fetch quietly rather than showing
        // whatever was true the day it was saved.
        .task { await refresh() }
        .confirmationDialog(
            "Remove “\(item.title)” from your library?",
            isPresented: $confirmingRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            backdrop

            HStack(alignment: .top, spacing: 14) {
                poster

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if item.isUpcoming {
                        Label("Upcoming", systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(.top, 2)
                    }

                    if !item.genres.isEmpty {
                        Text(item.genres.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, -30) // lift the poster over the backdrop's fade
        }
    }

    /// The release date, spelled out — always the day TMDB published, whatever
    /// time zone the phone is in (see `ReleaseDate`).
    private var metaLine: String {
        [item.mediaType.displayName, item.releaseDateText ?? "Release date unknown"]
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var backdrop: some View {
        let url = TMDBService.backdropURL(path: item.backdropPath)
            ?? TMDBService.posterURL(path: item.posterPath, size: .large)

        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.white.opacity(0.05))
        }
        .frame(height: 210)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay {
            // Fade the artwork into the page so the poster below it doesn't sit
            // on a hard edge.
            LinearGradient(
                colors: [.clear, .bingeGround.opacity(0.7), .bingeGround],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var poster: some View {
        MediaPosterView(
            title: item.title,
            posterPath: item.posterPath,
            mediaType: item.mediaType,
            showsCaption: false // the title is right beside it
        )
        .frame(width: 100)
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
                .foregroundStyle(.white)
            Text(item.overview)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Where to stream

    private var streamingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Where to watch")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            if let refreshError {
                Text(refreshError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !settings.isConfigured {
                Text("Add your TMDB token in Settings to see streaming availability.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if item.streamingProviders.isEmpty {
                // A legitimate answer, not an error — plenty of titles stream
                // nowhere in a given country. Say so explicitly rather than
                // leaving a blank space the user has to interpret.
                Text(isRefreshing
                     ? "Checking…"
                     : "Not available to stream in \(settings.regionDisplayName).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                if !item.streamingOffers.isEmpty {
                    providerRow("Stream", providers: item.streamingOffers)
                }
                if !item.rentOrBuyOffers.isEmpty {
                    providerRow("Rent or buy", providers: item.rentOrBuyOffers)
                }

                Text("Availability in \(settings.regionDisplayName), via TMDB.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    private func providerRow(_ title: String, providers: [StreamingProvider]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(providers) { provider in
                        VStack(spacing: 4) {
                            AsyncImage(url: TMDBService.logoURL(path: provider.logoPath)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.08))
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                            Text(provider.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 56)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            // Reminders only make sense for something you still mean to watch and
            // that isn't out yet. Offering the toggle otherwise would be a switch
            // that flips on and silently does nothing — `isEligible` is pinned to
            // agree with what the scheduler will actually accept.
            if ReleaseReminder.isEligible(item) {
                Toggle(isOn: reminderBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me when it's out")
                        Text("Morning of release day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.accentColor)
                .padding()

                if notificationsDenied {
                    Text("Notifications are turned off for Binge. Turn them on in the Settings app to get release reminders.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                Divider().overlay(.white.opacity(0.1))
            }

            Button {
                Task { await setStatus(item.watchStatus == .watched ? .wantToWatch : .watched) }
            } label: {
                Label(
                    item.watchStatus == .watched ? "Move to Want to Watch" : "Mark as Watched",
                    systemImage: item.watchStatus == .watched ? "bookmark" : "checkmark.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            Divider().overlay(.white.opacity(0.1))

            Button(role: .destructive) {
                confirmingRemove = true
            } label: {
                Label("Remove from Library", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    // MARK: - Reminder

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { item.reminderScheduled },
            set: { wantsReminder in
                Task {
                    if wantsReminder {
                        let scheduled = await NotificationManager.shared.enable(for: item)
                        // `enable` already cleared the flag on failure, so the
                        // toggle snaps back on its own. All that's left is saying
                        // why — otherwise it just looks broken.
                        if scheduled {
                            notificationsDenied = false
                        } else {
                            let status = await NotificationManager.shared.authorizationStatus
                            notificationsDenied = status == .denied
                        }
                    } else {
                        await NotificationManager.shared.disable(for: item)
                        notificationsDenied = false
                    }
                    try? modelContext.save()
                }
            }
        )
    }

    // MARK: - Mutations

    private func setStatus(_ status: WatchStatus) async {
        item.watchStatus = status
        try? modelContext.save()

        // Marking something watched must cancel its pending reminder — being told
        // a film you've already seen is "out today" is exactly the drift the plan
        // warns about.
        await NotificationManager.shared.sync(item)
        try? modelContext.save()
    }

    private func remove() {
        // Grab the key *before* deleting: afterwards the item is gone from the
        // context and its properties are no longer safe to read.
        let key = item.uniqueKey
        NotificationManager.shared.cancel(forKey: key)

        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Refresh

    /// Re-fetch details and the provider snapshot. Best-effort: a failure leaves
    /// what's already stored on screen rather than blanking the page.
    private func refresh() async {
        guard settings.isConfigured, !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        let service = TMDBService(settings: settings)
        let region = settings.region

        if let details = try? await service.details(for: item.tmdbId, mediaType: item.mediaType) {
            let previousDate = item.releaseDate

            item.title = details.title.isEmpty ? item.title : details.title
            item.overview = details.overview.isEmpty ? item.overview : details.overview
            item.posterPath = details.posterPath ?? item.posterPath
            item.backdropPath = details.backdropPath ?? item.backdropPath
            item.genres = details.genres
            item.releaseDate = details.releaseDate

            // TMDB revises release dates all the time. A reminder pinned to the
            // old date would fire on the wrong day, so follow the change.
            if previousDate != details.releaseDate {
                await NotificationManager.shared.sync(item)
            }
        }

        do {
            let providers = try await service.watchProviders(
                for: item.tmdbId,
                mediaType: item.mediaType,
                region: region
            )
            item.streamingProviders = providers
            item.providersRegion = region
            item.providersUpdatedAt = .now
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }

        try? modelContext.save()
    }
}
