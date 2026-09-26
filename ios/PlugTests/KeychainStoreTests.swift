import XCTest
@testable import Plug

/// Proves the two things the phase is judged on for storage: a saved credential comes back
/// after the process that wrote it is gone, and a deleted one does not.
///
/// The Keychain refuses an application that carries no entitlement, which is exactly what
/// an unsigned simulator build is — CI passes CODE_SIGNING_ALLOWED=NO. These tests skip
/// there rather than being deleted, so they still run wherever signing is on, and the
/// relaunch behaviour on a real device is recorded as gate evidence under evidence/P1/ios.
final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore()
    private let account = "keychain-store-tests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        do {
            try store.save(Data("probe".utf8), account: account)
            try store.delete(account: account)
        } catch KeychainError.unableToSave(errSecMissingEntitlement) {
            throw XCTSkip("This build is unsigned, so the Keychain is unavailable to the test host.")
        }
    }

    override func tearDown() {
        try? store.delete(account: account)
        super.tearDown()
    }

    func testSavedCredentialsAreReadBack() throws {
        try store.save(Data("first".utf8), account: account)
        XCTAssertEqual(try store.read(account: account), Data("first".utf8))
    }

    func testSavingAgainReplacesRatherThanDuplicates() throws {
        try store.save(Data("first".utf8), account: account)
        try store.save(Data("second".utf8), account: account)
        XCTAssertEqual(try store.read(account: account), Data("second".utf8))
    }

    func testDeletingRemovesTheCredentialAndIsSafeToRepeat() throws {
        try store.save(Data("first".utf8), account: account)
        try store.delete(account: account)
        XCTAssertNil(try store.read(account: account))
        XCTAssertNoThrow(try store.delete(account: account))
    }

    func testReadingAnUnknownAccountIsNotAnError() throws {
        XCTAssertNil(try store.read(account: "never-written-\(UUID().uuidString)"))
    }
}
