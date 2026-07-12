import Foundation
import Testing
@testable import Binge

/// The reminder *decision* — the part the plan flags as most correctness-sensitive.
///
/// All of it is pure, so every edge is tested here rather than being discovered
/// on a real device at 9am on a release day.
@Suite("Release reminders")
struct ReleaseReminderTests {

    private func item(
        release: String?,
        status: WatchStatus = .wantToWatch,
        type: MediaType = .movie
    ) -> MediaItem {
        MediaItem(
            tmdbId: 693134,
            mediaType: type,
            title: "Dune: Part Two",
            releaseDate: ReleaseDate.parse(release),
            watchStatus: status
        )
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// An instant on a given local day/hour, for driving `now`.
    private func instant(_ zone: String, _ y: Int, _ m: Int, _ d: Int, _ hour: Int) -> Date {
        calendar(zone).date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: - Eligibility

    @Test("a future release gets a reminder at 9am on release day")
    func futureReleaseSchedules() throws {
        let dune = item(release: "2030-03-01")
        let components = try #require(
            ReleaseReminder.fireComponents(for: dune, now: instant("UTC", 2030, 1, 1, 12))
        )

        #expect(components.year == 2030)
        #expect(components.month == 3)
        #expect(components.day == 1)
        #expect(components.hour == 9)
    }

    @Test("the components carry no time zone, so the reminder follows the user")
    func componentsAreTimeZoneFree() throws {
        let dune = item(release: "2030-03-01")
        let components = try #require(
            ReleaseReminder.fireComponents(for: dune, now: instant("UTC", 2030, 1, 1, 12))
        )

        // This is what makes the reminder fire at 9am *local* even if the user
        // flies somewhere else after scheduling it. Pinning a time zone here
        // would freeze the offset and fire at the wrong hour.
        #expect(components.timeZone == nil)
        #expect(components.calendar == nil)
    }

    @Test("a watched title never gets a reminder")
    func watchedIsIneligible() {
        let watched = item(release: "2030-03-01", status: .watched)
        #expect(ReleaseReminder.fireComponents(for: watched, now: instant("UTC", 2030, 1, 1, 12)) == nil)
    }

    @Test("a title with no release date never gets a reminder")
    func undatedIsIneligible() {
        let undated = item(release: nil)
        #expect(ReleaseReminder.fireComponents(for: undated, now: .now) == nil)
    }

    @Test("a release that has already passed gets no reminder")
    func pastReleaseIsIneligible() {
        let old = item(release: "1999-01-01")
        #expect(ReleaseReminder.fireComponents(for: old, now: instant("UTC", 2030, 1, 1, 12)) == nil)
    }

    // MARK: - The release-day boundary

    @Test("released today at 7am — the 9am reminder is still ahead, so it schedules")
    func todayBeforeNine() throws {
        let today = item(release: "2030-03-01")
        let sevenAM = instant("UTC", 2030, 3, 1, 7)

        let components = try #require(
            ReleaseReminder.fireComponents(for: today, now: sevenAM, calendar: calendar("UTC"))
        )
        #expect(components.day == 1)
        #expect(components.hour == 9)
    }

    @Test("released today at 3pm — 9am is gone, and a past trigger never fires")
    func todayAfterNine() {
        let today = item(release: "2030-03-01")
        let threePM = instant("UTC", 2030, 3, 1, 15)

        // The bug this prevents: happily "scheduling" a notification for 9am
        // today, which iOS silently drops because it's in the past. The user
        // sees a toggle flip on and then nothing ever arrives.
        #expect(
            ReleaseReminder.fireComponents(for: today, now: threePM, calendar: calendar("UTC")) == nil
        )
    }

    // MARK: - Time zones (the whole reason ReleaseDate exists)

    /// The release day must be read in **UTC**, because that's how it's stored.
    /// Reading it with a local calendar west of Greenwich yields the previous day
    /// — which would fire the reminder a day *early*.
    @Test(
        "the reminder lands on the published day in every time zone",
        arguments: ["America/Los_Angeles", "Pacific/Midway", "Asia/Kolkata", "Pacific/Kiritimati", "UTC"]
    )
    func firesOnPublishedDayEverywhere(_ zone: String) throws {
        let dune = item(release: "2030-03-01")

        let components = try #require(
            ReleaseReminder.fireComponents(
                for: dune,
                now: instant(zone, 2030, 1, 1, 12),
                calendar: calendar(zone)
            )
        )

        // March 1st. Not February 28th, not March 2nd.
        #expect(components.year == 2030)
        #expect(components.month == 3)
        #expect(components.day == 1)
        #expect(components.hour == 9)
    }

    // MARK: - Identifiers (the duplicate guard)

    @Test("the reminder id is derived from the item, so re-scheduling replaces")
    func identifierIsStable() {
        let dune = item(release: "2030-03-01")

        // Same item → same id → `center.add` replaces rather than duplicating.
        // This is the entire duplicate-scheduling defence.
        #expect(ReleaseReminder.identifier(for: dune) == "release-movie-693134")
        #expect(ReleaseReminder.identifier(for: dune) == ReleaseReminder.identifier(for: dune))
        #expect(ReleaseReminder.isReminderIdentifier(ReleaseReminder.identifier(for: dune)))
    }

    @Test("a movie and a show with the same TMDB id get different reminders")
    func identifierIsCompositeAcrossMediaTypes() {
        // TMDB ids are only unique *within* a media type — the reason MediaItem's
        // key is composite in the first place. A non-composite id here would make
        // adding a show cancel a movie's reminder.
        let movie = item(release: "2030-03-01", type: .movie)
        let show = item(release: "2030-03-01", type: .tv)

        #expect(ReleaseReminder.identifier(for: movie) != ReleaseReminder.identifier(for: show))
    }

    @Test("we only ever prune our own notifications")
    func identifierNamespacing() {
        #expect(ReleaseReminder.isReminderIdentifier("release-movie-1"))
        #expect(!ReleaseReminder.isReminderIdentifier("some-other-feature-1"))
    }

    // MARK: - isEligible mirrors fireComponents

    @Test("isEligible agrees with fireComponents, so the toggle never lies")
    func eligibilityMatchesScheduling() {
        let now = instant("UTC", 2030, 1, 1, 12)

        let cases: [(MediaItem, Bool)] = [
            (item(release: "2030-03-01"), true),
            (item(release: "1999-01-01"), false),
            (item(release: nil), false),
            (item(release: "2030-03-01", status: .watched), false)
        ]

        for (item, expected) in cases {
            // The detail screen shows the toggle based on isEligible and schedules
            // based on fireComponents. If they ever disagree, the user gets a
            // switch that flips on and does nothing.
            #expect(ReleaseReminder.isEligible(item, now: now) == expected)
            #expect((ReleaseReminder.fireComponents(for: item, now: now) != nil) == expected)
        }
    }
}
