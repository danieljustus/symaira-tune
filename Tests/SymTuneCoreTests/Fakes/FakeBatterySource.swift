import Foundation
@testable import SymTuneCore

struct FakeBatterySource: BatterySource, Sendable {
    var result: BatterySourceResult = .unavailable

    func readProperties() -> BatterySourceResult {
        result
    }
}
