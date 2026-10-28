import Foundation
import Security

/// Each account's Secret Access Key as a generic password in the user's Keychain.
nonisolated enum Keychain {
    /// The app identifier from Info.plist – changing CFBundleIdentifier at build time also changes where secrets live.
    private static let service = Bundle.main.bundleIdentifier ?? "aws-account-mixer"

    static func setSecret(_ secret: String, for id: UUID, label: String) throws {
        let query = baseQuery(for: id)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrLabel as String: label,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func secret(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func deleteSecret(for id: UUID) {
        SecItemDelete(baseQuery(for: id) as CFDictionary)
    }

    private static func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}

nonisolated struct KeychainError: LocalizedError {
    var status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return String(localized: "Couldn't save the key to the Keychain: \(message)")
    }
}
