import XCTest
@testable import SymTuneCore

final class KeychainCredentialsTests: XCTestCase {
    private let service = "com.symaira.symtune.test"
    private let account = "test-\(UUID().uuidString)"

    override func tearDown() {
        _ = KeychainCredentials.delete(service: service, account: account)
        super.tearDown()
    }

    /// Round-trips a value through the Keychain. Skips (not fails) when the
    /// test environment has no usable keyring (e.g. headless CI).
    func testWriteReadDeleteRoundTrip() throws {
        let secret = "test-secret-\(UUID().uuidString)"
        guard KeychainCredentials.write(service: service, account: account, value: secret) else {
            throw XCTSkip("keychain unavailable in this environment")
        }

        XCTAssertEqual(KeychainCredentials.read(service: service, account: account), secret)

        // Overwrite replaces the previous value.
        let second = "test-secret-2-\(UUID().uuidString)"
        XCTAssertTrue(KeychainCredentials.write(service: service, account: account, value: second))
        XCTAssertEqual(KeychainCredentials.read(service: service, account: account), second)

        XCTAssertTrue(KeychainCredentials.delete(service: service, account: account))
        XCTAssertNil(KeychainCredentials.read(service: service, account: account))
    }

    func testDeleteIsIdempotent() {
        XCTAssertTrue(KeychainCredentials.delete(service: service, account: account))
        XCTAssertTrue(KeychainCredentials.delete(service: service, account: account))
    }
}
