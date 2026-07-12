import Foundation

/// Decides **whether** and **when** a release reminder should fire.
///
/// Deliberately pure — no `UserNotifications`, no I/O — because every edge the
/// plan flags as easy to get subtly wrong lives *here*, not in the scheduling
/// call: past dates, missing dates, time zones, and titles that have quietly
/// stopped being eligible. Pure means all of it is unit-testable without a device
/// and without granting notification permission.
enum ReleaseReminder {

    /// The hour of release day we nudge at, in the user's **local** time.
    /// Not midnight: a notification at 00:00 either wakes the user or is missed.
    static let hour = 9

    /// The calendar components a reminder for `item` should fire at, or `nil` if
    /// it shouldn't have one at all.
    ///
    /// Returns `DateComponents` rather than an absolute `Date` on purpose. The
    /// components carry no time zone, so `UNCalendarNotificationTrigger` resolves
    /// them against whatever calendar is current **when the trigger fires** — the
    /// reminder lands at 9am local on release day even if the user flies somewhere
    /// else between scheduling it and the release. An absolute `Date` would freeze
    /// the offset at scheduling time and fire at the wrong local hour.
    ///
    /// - Parameters:
    ///   - now: injectable so the "already passed" boundary is testable.
    ///   - calendar: the *local* calendar, injectable for the same reason. Note
    ///     this is only used to resolve the fire instant for the past-check — the
    ///     release **day** itself is read in UTC (below), which is the whole point.
    static func fireComponents(
        for item: MediaItem,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DateComponents? {
        // A title you've already watched doesn't need telling it's out.
        guard item.watchStatus == .wantToWatch else { return nil }

        // No date, no reminder. TMDB genuinely doesn't know for a lot of titles.
        guard let releaseDate = item.releaseDate else { return nil }

        // Read the published day in UTC — release dates are floating calendar
        // dates pinned to midnight UTC (see `ReleaseDate`). Reading it with the
        // *local* calendar is exactly the off-by-one that would fire the reminder
        // a day early for anyone west of Greenwich.
        let published = ReleaseDate.calendar.dateComponents(
            [.year, .month, .day],
            from: releaseDate
        )
        guard let year = published.year,
              let month = published.month,
              let day = published.day
        else { return nil }

        var fire = DateComponents()
        fire.year = year
        fire.month = month
        fire.day = day
        fire.hour = Self.hour
        // No `timeZone` and no `calendar` set — see the note above.

        // A trigger in the past simply never fires. Report "no reminder" rather
        // than claiming to have scheduled one that will never arrive.
        guard let fireDate = calendar.date(from: fire), fireDate > now else { return nil }

        return fire
    }

    /// Whether a reminder can be offered for this title at all — drives whether
    /// the detail screen shows the toggle, so the UI never offers a switch that
    /// silently does nothing.
    static func isEligible(
        _ item: MediaItem,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        fireComponents(for: item, now: now, calendar: calendar) != nil
    }

    /// The notification request id for a title.
    ///
    /// Derived from the item's composite key, which makes scheduling idempotent:
    /// re-adding a request with the same identifier *replaces* the old one, so a
    /// double-tap or a re-sync can't produce two notifications for one title.
    static func identifier(for item: MediaItem) -> String {
        identifier(forKey: item.uniqueKey)
    }

    static func identifier(forKey uniqueKey: String) -> String {
        "release-\(uniqueKey)"
    }

    /// True for identifiers this type owns, so reconciliation can prune its own
    /// pending requests without touching anything else the app might schedule later.
    static func isReminderIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("release-")
    }
}
