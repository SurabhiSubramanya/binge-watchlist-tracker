#if DEBUG
import Foundation

/// Temporary Subtask-3 verification harness.
///
/// Exercises ``Keychain`` and ``AppSettings`` end-to-end on the real device
/// Keychain: write → read back → overwrite → clear, plus the read-through that
/// makes a *fresh* `AppSettings` see what a previous one persisted. That
/// read-through is the whole point of the subtask, and it's the part that a
/// pure in-memory test would happily fake.
///
/// Runs against a scratch Keychain account and a scratch `UserDefaults` suite,
/// so it never touches the user's real token or region, and cleans both up.
///
/// Removed alongside ``ModelSelfCheck`` in Subtask 5, when the real Settings
/// screen makes this observable through the UI instead.
enum SettingsSelfCheck {
    private static let testAccount = "selfcheck-tmdb-token"
    private static let testSuite = "com.binge.Binge.selfcheck"

    static func run() -> String {
        defer { cleanUp() }

        guard let defaults = UserDefaults(suiteName: testSuite) else {
            return "✗ couldn't open scratch defaults suite"
        }
        cleanUp() // start from a known-empty slate even if a prior run crashed

        do {
            // 1. Keychain round-trip, including overwrite and clear.
            try Keychain.set("first-token", for: testAccount)
            guard Keychain.read(testAccount) == "first-token" else {
                return "✗ keychain read-back failed"
            }

            try Keychain.set("second-token", for: testAccount)
            guard Keychain.read(testAccount) == "second-token" else {
                return "✗ keychain overwrite failed"
            }

            try Keychain.set("", for: testAccount)
            guard Keychain.read(testAccount) == nil else {
                return "✗ empty value should clear the keychain item"
            }

            // 2. A fresh, unconfigured store.
            let settings = AppSettings(defaults: defaults, tokenAccount: testAccount)
            guard settings.tmdbToken.isEmpty,
                  !settings.isConfigured,
                  settings.bearerToken == nil
            else { return "✗ fresh settings should be unconfigured" }

            guard !settings.region.isEmpty, settings.region == settings.region.uppercased() else {
                return "✗ region should default to an uppercase code (got \(settings.region))"
            }
            let defaultRegion = settings.region

            // 3. Assigning a token trims it, configures the app, and persists.
            settings.tmdbToken = "  eyJhbGciOi.test.token \n"
            guard settings.tmdbToken == "eyJhbGciOi.test.token" else {
                return "✗ token not trimmed (got \(settings.tmdbToken))"
            }
            guard settings.isConfigured,
                  settings.bearerToken == "eyJhbGciOi.test.token"
            else { return "✗ token should configure the app" }

            // 4. Assigning a region normalizes it.
            settings.region = " gb "
            guard settings.region == "GB" else {
                return "✗ region not normalized (got \(settings.region))"
            }

            // 5. The read-through: a brand-new store sees both persisted values.
            //    This is what a real relaunch does.
            let reloaded = AppSettings(defaults: defaults, tokenAccount: testAccount)
            guard reloaded.tmdbToken == "eyJhbGciOi.test.token", reloaded.isConfigured else {
                return "✗ token did not survive a reload"
            }
            guard reloaded.region == "GB" else {
                return "✗ region did not survive a reload (got \(reloaded.region))"
            }

            // 6. Clearing removes the secret from the Keychain, not just memory.
            reloaded.clearToken()
            guard !reloaded.isConfigured, reloaded.bearerToken == nil else {
                return "✗ clearToken should unconfigure the app"
            }
            guard Keychain.read(testAccount) == nil else {
                return "✗ clearToken left the token in the keychain"
            }

            return "✓ settings OK · keychain round-trip · reload · region \(defaultRegion)→GB"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }

    /// Leave no trace: drop the scratch Keychain item and the scratch suite.
    private static func cleanUp() {
        try? Keychain.remove(testAccount)
        UserDefaults.standard.removePersistentDomain(forName: testSuite)
    }
}
#endif
