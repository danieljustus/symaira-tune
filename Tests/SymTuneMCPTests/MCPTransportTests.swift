import XCTest
@testable import SymTuneMCP
import SymTuneCore

final class MCPTransportTests: XCTestCase {
    /// Mirrors the production maximum so boundary tests can use small, fast payloads.
    private let maxPayloadSize = 8 * 1024 * 1024

    // MARK: - Payload size limit

    func testRejectsOversizedContentLength() throws {
        let header = Data("Content-Length: \(maxPayloadSize + 1)\r\n\r\n".utf8)
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(header)
        pipe.fileHandleForWriting.closeFile()

        let reading = MCPTransport(input: pipe.fileHandleForReading, output: .nullDevice)
        XCTAssertThrowsError(try reading.readMessage()) { error in
            guard let tuneError = error as? TuneError else {
                return XCTFail("Expected TuneError, got \(error)")
            }
            switch tuneError {
            case .failed(let message):
                XCTAssertTrue(message.contains("exceeds maximum allowed"), "message was: \(message)")
            default:
                XCTFail("Expected .failed error, got \(tuneError)")
            }
        }
    }

    func testAcceptsPayloadExactlyAtLimit() throws {
        // The production limit is 8 MiB. Verify the boundary by checking that
        // a header declaring exactly 8 MiB is accepted *before* reading the body.
        let header = Data("Content-Length: \(maxPayloadSize)\r\n\r\n".utf8)
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(header)
        pipe.fileHandleForWriting.closeFile()

        let reading = MCPTransport(input: pipe.fileHandleForReading, output: .nullDevice)
        // Should not throw the oversized error; the read will EOF, which is fine for this assertion.
        XCTAssertThrowsError(try reading.readMessage()) { error in
            guard let tuneError = error as? TuneError else {
                return XCTFail("Expected TuneError, got \(error)")
            }
            switch tuneError {
            case .failed(let message):
                XCTAssertFalse(message.contains("exceeds maximum allowed"), "Should not reject at-limit payload: \(message)")
            default:
                break
            }
        }
    }

    // MARK: - Header overflow

    func testRejectsHeaderWithoutTerminator() throws {
        let oversizedHeader = Data(repeating: 0x20, count: 8192)
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(oversizedHeader)
        pipe.fileHandleForWriting.closeFile()

        let transport = MCPTransport(input: pipe.fileHandleForReading, output: .nullDevice)
        XCTAssertThrowsError(try transport.readMessage()) { error in
            guard let tuneError = error as? TuneError else {
                return XCTFail("Expected TuneError, got \(error)")
            }
            switch tuneError {
            case .failed(let message):
                XCTAssertTrue(message.contains("exceeded 8192 bytes without terminator"), "message was: \(message)")
            default:
                XCTFail("Expected .failed error, got \(tuneError)")
            }
        }
    }
}
