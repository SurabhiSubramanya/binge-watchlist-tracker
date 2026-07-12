import Foundation
import UserNotifications

/// Schedules and cancels release-day reminders.
///
/// The *decision* — whether a title deserves a reminder and when it should fire —
/// lives in ``ReleaseReminder``, which is pure and tested. This type is only the
/// side-effecting shell around `UNUserNotificationCenter`, kept deliberately thin
/// because none of it can be unit-tested on a simulator without real permission.
///
/// Reminders are **opt-in per title** (the toggle on the detail screen), and the
/// `MediaItem.reminderScheduled` flag records that intent. Keeping that flag and
/// the actual pending notifications in agreement is the thing the plan calls out
/// as easiest to get wrong, so every mutation goes through `sync(_:)`.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorization

    var authorizationStatus: UNAuthorizationStatus {
        get async { await center.notificationSettings().authorizationStatus }
    }

    /// Asks for permission, but only the first time — iOS silently ignores a
    /// second prompt, so a `denied` user must be sent to Settings instead of
    /// being asked again into the void.
    @discardableResult
    func requestAuthorization() async -> Bool {
        switch await authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - The toggle

    /// Turn the reminder on for a title.
    ///
    /// Returns `false` — and leaves `reminderScheduled` false — if permission was
    /// refused or the release has already passed. The caller can then tell the
    /// user *why* rather than showing a switch that flipped on and did nothing.
    @discardableResult
    func enable(for item: MediaItem) async -> Bool {
        guard let components = ReleaseReminder.fireComponents(for: item) else {
            // Not eligible (watched, undated, or already out).
            await disable(for: item)
            return false
        }

        guard await requestAuthorization() else {
            item.reminderScheduled = false
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.mediaType == .movie
            ? "Out today. Time to watch it."
            : "Out today. First episode's up."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: ReleaseReminder.identifier(for: item),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            // Same identifier replaces any existing request — that's the
            // duplicate guard, and it's why the id is derived from the item.
            try await center.add(request)
            item.reminderScheduled = true
            return true
        } catch {
            item.reminderScheduled = false
            return false
        }
    }

    /// Turn the reminder off.
    func disable(for item: MediaItem) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [ReleaseReminder.identifier(for: item)]
        )
        item.reminderScheduled = false
    }

    /// Cancel by key, for a title that's being deleted — by which point the
    /// `MediaItem` may already be gone from the context.
    func cancel(forKey uniqueKey: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: [ReleaseReminder.identifier(forKey: uniqueKey)]
        )
    }

    // MARK: - Staying in sync

    /// Re-assert the scheduled state after a title changed.
    ///
    /// Call this whenever anything a reminder depends on moves: the watch status
    /// (marked watched → cancel), or the release date (TMDB revised it → reschedule
    /// to the new day). This is what stops a reminder firing for something the
    /// user already watched.
    func sync(_ item: MediaItem) async {
        guard item.reminderScheduled else {
            // The user never asked for one. Still clear any stale request — the
            // flag is the source of truth, and drift is the bug we're preventing.
            center.removePendingNotificationRequests(
                withIdentifiers: [ReleaseReminder.identifier(for: item)]
            )
            return
        }

        guard ReleaseReminder.isEligible(item) else {
            // It *was* wanted, but the title is now watched, undated, or out.
            await disable(for: item)
            return
        }

        // Still eligible — re-add, which replaces the pending request in case the
        // date moved underneath us.
        await enable(for: item)
    }

    /// Cancel every pending reminder that no longer corresponds to a title that
    /// should have one.
    ///
    /// The safety net for the drift the plan warns about: a title deleted while
    /// the app wasn't running, a date TMDB pulled, a `reminderScheduled` flag that
    /// somehow disagrees with reality. Cheap enough to run at launch.
    func reconcile(with items: [MediaItem]) async {
        let pending = await center.pendingNotificationRequests()

        let shouldExist: Set<String> = Set(
            items
                .filter { $0.reminderScheduled && ReleaseReminder.isEligible($0) }
                .map { ReleaseReminder.identifier(for: $0) }
        )

        // 1. Prune. A reminder for a title that's been watched, deleted, or has
        //    since come out. Needs no permission, so it always runs.
        let orphans = pending
            .map(\.identifier)
            .filter { ReleaseReminder.isReminderIdentifier($0) && !shouldExist.contains($0) }

        if !orphans.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: orphans)
        }

        // 2. Drop the flag on anything that can no longer have a reminder, so the
        //    detail screen's toggle doesn't show "on" for a title that's out.
        for item in items where item.reminderScheduled && !ReleaseReminder.isEligible(item) {
            item.reminderScheduled = false
        }

        // 3. Re-add anything missing — but ONLY if permission already exists.
        //
        //    `enable` would otherwise call `requestAuthorization`, and reconcile
        //    runs at launch: that would prompt for notification permission the
        //    moment the app opens, before the user has asked for a single
        //    reminder. Permission gets requested when they flip the toggle, and
        //    at no other time.
        let status = await authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let pendingIds = Set(pending.map(\.identifier))
        for item in items where item.reminderScheduled {
            if !pendingIds.contains(ReleaseReminder.identifier(for: item)) {
                await enable(for: item)
            }
        }
    }
}
