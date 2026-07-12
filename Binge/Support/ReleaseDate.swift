import Foundation

/// Release dates are **floating calendar dates**, not instants.
///
/// TMDB publishes `"2024-02-27"` — no time, no time zone. `Date` can only hold
/// an instant, so every release date is pinned to **midnight UTC** on the day
/// TMDB published, and always read back through a **UTC calendar**. Both ends
/// agree, so the day the user sees is the day TMDB published — in every time
/// zone, forever.
///
/// The tempting alternative is to pin to *local* midnight and read back with
/// `Calendar.current`. That looks correct right up until the phone changes time
/// zone: the stored instant then formats as the previous (or next) day. That's
/// the classic release-date off-by-one, and it's why this type exists.
///
/// **Anything that touches `MediaItem.releaseDate` must go through here.**
/// Reaching for `Calendar.current` directly is exactly how the bug comes back.
enum ReleaseDate {
    /// The calendar release dates are stored in and read back through. UTC, always.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// `"2024-02-27"` → midnight UTC that day.
    ///
    /// `nil` for TMDB's `""` and `null`, and for anything that isn't a plain
    /// `yyyy-MM-dd` — a partial date like `"2024"` is not a release date.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }

        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The four-digit year — read in UTC, so it can't slip across a New Year.
    static func year(of date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    /// The published day, formatted the way the user's region writes dates.
    ///
    /// The *calendar* stays UTC so the day is right; the *locale* is the user's
    /// so they get "27 February 2024" or "February 27, 2024" as appropriate.
    static func formatted(_ date: Date, style: DateFormatter.Style = .long) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Whether the title comes out on a day *after* the user's today.
    ///
    /// Deliberately a day-to-day comparison, not `date > .now`. Comparing
    /// instants gets tomorrow's release wrong from mid-afternoon anywhere with a
    /// negative UTC offset, because tomorrow's *UTC* midnight has already passed
    /// in local time.
    static func isUpcoming(_ date: Date) -> Bool {
        date > todayAsFloatingDate
    }

    /// The user's today, expressed the same way release dates are — midnight UTC
    /// on that day — so the two are directly comparable.
    static var todayAsFloatingDate: Date {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return calendar.date(
            from: DateComponents(year: today.year, month: today.month, day: today.day)
        ) ?? .now
    }
}
