import Foundation
import Security

/// A minimal wrapper over the iOS Keychain for the app's secrets — today just
/// the TMDB v4 Read Access Token.
///
/// Secrets are stored as generic-password items namespaced under this app's
/// service, so they never touch `UserDefaults` (world-readable from a device
/// backup) and never get committed to source.
enum Keychain {
    /// Namespaces our items so they can't collide with another app's.
    private static let service = "com.binge.Binge"

    enum KeychainError: Error, LocalizedError {
        /// The Security framework returned something other than success.
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    /// Store `value` for `account`, replacing anything already there.
    ///
    /// An empty (or whitespace-only) value is treated as a clear: the item is
    /// removed rather than stored blank, so `read` stays "nil means unset".
    static func set(_ value: String, for account: String) throws {
        // Delete-then-add so this is an unconditional upsert. `SecItemUpdate`
        // would need a separate not-found path for the first write.
        try remove(account)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Readable after the first unlock following a boot — enough for a
            // background refresh, and never leaves the device (no iCloud sync,
            // which also keeps us off the paid-account entitlement path).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// The value stored for `account`, or `nil` if there isn't one.
    ///
    /// Reads are non-throwing on purpose: every caller treats "no token" and
    /// "couldn't read the token" the same way — prompt the user for one.
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }

        return value
    }

    /// Remove the item for `account`. Removing a missing item is a no-op, not
    /// an error — that keeps `set` (which always deletes first) simple.
    static func remove(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
