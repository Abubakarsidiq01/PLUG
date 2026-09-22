import Foundation
@testable import Plug

/// Stands in for the Keychain so the session tests can run anywhere and can assert on what
/// was written. The real KeychainStore has its own tests; this one exists so that a failure
/// in a session test points at session logic rather than at device storage.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[account] = data
    }

    func read(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }

    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return items.isEmpty
    }
}
