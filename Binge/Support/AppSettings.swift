import Foundation
import Observation

/// App-wide configuration, injected into the SwiftUI environment.
///
/// Two settings, two homes:
/// - the **TMDB token** is a secret, so it lives in the Keychain (``Keychain``);
/// - the **region** is a harmless preference, so it lives in `UserDefaults`.
///
/// Both are written through immediately on assignment, so a screen can just bind
/// to `settings.region` / `settings.tmdbToken` and persistence takes care of itself.
@Observable
final class AppSettings {
    /// Keys for the two backing stores. The token key is a Keychain *account*;
    /// the region key is a `UserDefaults` key.
    private enum Key {
        static let tmdbToken = "tmdb-read-access-token"
        static let region = "streaming-providers-region"
    }

    /// Where we fall back when the device has no region (rare, but `Locale`
    /// makes it optional, and TMDB needs *some* region to return providers).
    static let fallbackRegion = "US"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tokenAccount: String

    // MARK: - Settings

    /// TMDB v4 Read Access Token, used as `Authorization: Bearer <token>`.
    ///
    /// Assigning persists to the Keychain; assigning an empty string clears it.
    var tmdbToken: String {
        didSet {
            // Keep the in-memory value canonical (trimmed) too — users paste
            // tokens and reliably bring a trailing newline along for the ride.
            // Assigning here does not re-enter `didSet`; Swift suppresses that.
            let trimmed = tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != tmdbToken { tmdbToken = trimmed }

            guard trimmed != oldValue else { return }
            try? Keychain.set(trimmed, for: tokenAccount)
        }
    }

    /// ISO 3166-1 region code (e.g. `US`) that streaming availability is looked
    /// up for. Providers are region-specific, so this changes what the app shows.
    var region: String {
        didSet {
            let normalized = Self.normalize(region)
            if normalized != region { region = normalized }

            guard normalized != oldValue else { return }
            defaults.set(normalized, forKey: Key.region)
        }
    }

    // MARK: - Derived

    /// True once a usable token has been entered. The UI gates every network
    /// feature on this and nudges the user to Settings when it's false.
    var isConfigured: Bool { !tmdbToken.isEmpty }

    /// The token to put in an `Authorization` header, or `nil` if unconfigured —
    /// lets the networking layer `guard let` its way to a clear "missing token"
    /// error instead of firing a request that's guaranteed to 401.
    var bearerToken: String? { isConfigured ? tmdbToken : nil }

    /// The region as something worth showing a human, e.g. `US` → "United States".
    var regionDisplayName: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - defaults: overridable so tests/self-checks can use a scratch suite.
    ///   - tokenAccount: overridable for the same reason — it keeps a test run
    ///     from stomping the real token.
    init(defaults: UserDefaults = .standard, tokenAccount: String = Key.tmdbToken) {
        self.defaults = defaults
        self.tokenAccount = tokenAccount

        // Read-through on launch: Keychain is the source of truth for the token,
        // UserDefaults for the region, and the device locale seeds a first run.
        self.tmdbToken = Keychain.read(tokenAccount) ?? ""
        self.region = Self.normalize(
            defaults.string(forKey: Key.region)
                ?? Locale.current.region?.identifier
                ?? Self.fallbackRegion
        )
    }

    /// Forget the stored token (Settings' "Remove token" action).
    func clearToken() {
        tmdbToken = ""
    }

    /// TMDB expects an uppercase ISO 3166-1 code; anything blank falls back.
    private static func normalize(_ region: String) -> String {
        let trimmed = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? fallbackRegion : trimmed
    }
}

#if DEBUG
extension AppSettings {
    /// A throwaway store for SwiftUI previews: scratch `UserDefaults` suite and
    /// scratch Keychain account, so a preview can never read — or clobber — the
    /// real token. This is what the injectable `init` exists for.
    static func preview(token: String = "", region: String = "US") -> AppSettings {
        let suite = "com.binge.Binge.preview"
        UserDefaults.standard.removePersistentDomain(forName: suite)

        let settings = AppSettings(
            defaults: UserDefaults(suiteName: suite) ?? .standard,
            tokenAccount: "preview-tmdb-token"
        )
        settings.tmdbToken = token
        settings.region = region
        return settings
    }
}
#endif
