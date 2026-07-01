import Foundation
@testable import SymTuneCore

final class FakePowerAssertionSource: PowerAssertionSource, @unchecked Sendable {
    var nextAssertionID: UInt32
    var shouldFailCreate: Bool = false
    var releaseAssertions: [UInt32] = []

    init(nextAssertionID: UInt32 = 123) {
        self.nextAssertionID = nextAssertionID
    }

    func create(type: PowerAssertionType, reason: String) throws -> UInt32 {
        if shouldFailCreate {
            throw TuneError.failed("simulated assertion failure")
        }
        return nextAssertionID
    }

    func release(_ assertionID: UInt32) {
        releaseAssertions.append(assertionID)
    }
}
