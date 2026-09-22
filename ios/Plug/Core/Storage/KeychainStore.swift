import Foundation
import Security

/// Tokens live in the Keychain. Never UserDefaults, never a plist, never a file, never a
/// log line, never an analytics property, never a crash breadcrumb (manual.docx 20.2).
///
/// The accessibility class matters as much as the choice of the Keychain itself:
/// `AfterFirstUnlockThisDeviceOnly` keeps the item out of an iCloud or iTunes backup and
/// out of reach before the device has been unlocked once since boot. A session that can be
/// restored from somebody's backup is not really revocable.
protocol CredentialStore {
    func save(_ data: Data, account: String) throws
    func read(account: String) throws -> Data?
    func delete(account: String) throws
}

enum KeychainError: Error, Equatable {
    case unableToSave(OSStatus)
    case unableToRead(OSStatus)
    case unableToDelete(OSStatus)
}

struct KeychainStore: CredentialStore {
    static let service = "app.plug.tokens"

    func save(_ data: Data, account: String) throws {
        var query = Self.query(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // Delete first rather than update: an item written under a different accessibility
        // class would otherwise keep that class for ever, and it would not be obvious.
        SecItemDelete(Self.query(account: account) as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unableToSave(status) }
    }

    func read(account: String) throws -> Data? {
        var query = Self.query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unableToRead(status) }
        return item as? Data
    }

    func delete(account: String) throws {
        let status = SecItemDelete(Self.query(account: account) as CFDictionary)
        // Deleting something that is not there is the outcome the caller wanted.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
