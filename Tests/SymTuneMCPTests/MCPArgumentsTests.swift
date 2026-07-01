import XCTest
@testable import SymTuneMCP
import SymTuneCore

final class MCPArgumentsTests: XCTestCase {

    // MARK: - requireDouble

    func testRequireDoubleAcceptsStringNumber() throws {
        let value = try requireDouble("3.14", name: "value")
        XCTAssertEqual(value, 3.14, accuracy: 0.001)
    }

    func testRequireDoubleAcceptsNSNumber() throws {
        let value = try requireDouble(2.71 as NSNumber, name: "value")
        XCTAssertEqual(value, 2.71, accuracy: 0.001)
    }

    func testRequireDoubleRejectsInvalidString() {
        XCTAssertThrowsError(try requireDouble("not-a-number", name: "value")) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("Missing required numeric argument 'value'"), msg)
        }
    }

    func testRequireDoubleRejectsNil() {
        XCTAssertThrowsError(try requireDouble(nil, name: "value")) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("Missing required numeric argument 'value'"), msg)
        }
    }

    // MARK: - requireInt

    func testRequireIntAcceptsStringNumber() throws {
        let value = try requireInt("42", name: "count")
        XCTAssertEqual(value, 42)
    }

    func testRequireIntAcceptsNSNumber() throws {
        let value = try requireInt(7 as NSNumber, name: "count")
        XCTAssertEqual(value, 7)
    }

    func testRequireIntRejectsInvalidString() {
        XCTAssertThrowsError(try requireInt("not-an-int", name: "count")) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("Missing required integer argument 'count'"), msg)
        }
    }

    func testRequireIntRejectsNil() {
        XCTAssertThrowsError(try requireInt(nil, name: "count")) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("Missing required integer argument 'count'"), msg)
        }
    }
}
