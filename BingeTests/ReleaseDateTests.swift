import Foundation
import Testing
@testable import Binge

/// Release dates are floating calendar dates. These tests pin the one property
/// the user actually cares about: **the day never shifts**.
///
/// Note on technique: an earlier version of these tests tried to simulate the
/// device being elsewhere by assigning `NSTimeZone.default`. That does *not*
/// reliably reach `Calendar.current`, so those tests passed no matter what the
/// implementation did — they proved nothing. Everything below constructs an
/// explicit `Calendar` instead, which is deterministic.
@Suite("Release dates")
struct ReleaseDateTests {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    // MARK: - Parsing

    @Test("a release date parses to the published day")
    func parsesToPublishedDay() throws {
        let date = try #require(ReleaseDate.parse("2024-02-27"))

        let parts = ReleaseDate.calendar.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2024)
        #expect(parts.month == 2)
        #expect(parts.day == 27)
    }

    @Test("non-dates are nil", arguments: [nil, "", "not-a-date", "2024", "2024-02"])
    func nonDatesAreNil(_ raw: String?) {
        #expect(ReleaseDate.parse(raw) == nil)
    }

    // MARK: - The bug this type exists to prevent

    /// West of UTC, midnight-UTC on the 27th is still the *26th* locally. Reading
    /// a release date with a device-time-zone calendar therefore hands back the
    /// wrong day — the classic release-date off-by-one.
    ///
    /// If someone ever "simplifies" `ReleaseDate.calendar` into `Calendar.current`,
    /// this is the test that should stop them.
    @Test(
        "a device-time-zone calendar slips the day west of UTC; ReleaseDate doesn't",
        arguments: ["America/Los_Angeles", "Pacific/Midway", "America/New_York"]
    )
    func deviceCalendarSlipsWestOfUTC(_ zone: String) throws {
        let date = try #require(ReleaseDate.parse("2024-02-27"))

        #expect(calendar(zone).component(.day, from: date) == 26, "this is the bug")
        #expect(ReleaseDate.calendar.component(.day, from: date) == 27, "ours stays correct")
    }

    /// East of UTC the day happens not to slip — midnight UTC is the same
    /// calendar day, just later in the morning. Pinned so the asymmetry is
    /// explicit rather than something someone rediscovers by accident.
    @Test(
        "east of UTC the day reads correctly either way",
        arguments: ["Asia/Kolkata", "Pacific/Kiritimati", "Europe/Berlin"]
    )
    func eastOfUTCDoesNotSlip(_ zone: String) throws {
        let date = try #require(ReleaseDate.parse("2024-02-27"))

        #expect(calendar(zone).component(.day, from: date) == 27)
        #expect(ReleaseDate.calendar.component(.day, from: date) == 27)
    }

    // MARK: - Display

    @Test("the formatted date shows the published day and year")
    func formattingShowsPublishedDay() throws {
        let date = try #require(ReleaseDate.parse("2024-02-27"))
        let text = ReleaseDate.formatted(date, style: .medium)

        // Not asserting exact wording — that follows the user's locale. Asserting
        // the thing that must never change: the day and the year.
        #expect(text.contains("27"))
        #expect(text.contains("2024"))
    }

    @Test("New Year's Day doesn't slip into the previous year")
    func yearDoesNotSlip() throws {
        let date = try #require(ReleaseDate.parse("2025-01-01"))

        #expect(ReleaseDate.year(of: date) == 2025)
        // Where a device calendar would say 2024-12-31.
        #expect(calendar("America/Los_Angeles").component(.year, from: date) == 2024)
    }

    // MARK: - Upcoming

    @Test("a title out tomorrow is upcoming; today's and yesterday's are not")
    func upcomingIsADayComparison() {
        let today = ReleaseDate.todayAsFloatingDate
        let day: TimeInterval = 86_400

        #expect(ReleaseDate.isUpcoming(today.addingTimeInterval(day)))
        #expect(!ReleaseDate.isUpcoming(today))
        #expect(!ReleaseDate.isUpcoming(today.addingTimeInterval(-day)))
    }

    /// `isUpcoming` compares *days*, not instants, and this is why. A naive
    /// `releaseDate > .now` would call tomorrow's release "already out" from
    /// mid-afternoon anywhere west of UTC, because tomorrow's midnight-UTC has
    /// already passed in local time.
    @Test("tomorrow's release isn't 'already out' just because UTC midnight passed")
    func upcomingSurvivesTheNaiveInstantComparison() {
        let tomorrow = ReleaseDate.todayAsFloatingDate.addingTimeInterval(86_400)

        #expect(ReleaseDate.isUpcoming(tomorrow))

        // The naive check this replaces: in a UTC-8 afternoon, `tomorrow` (stored
        // as midnight UTC) is already in the past, so `> .now` would say false.
        // Documented rather than asserted, since it depends on the clock.
    }
}
