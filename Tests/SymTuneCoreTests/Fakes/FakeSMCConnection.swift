import Foundation
@testable import SymTuneCore

final class FakeSMCConnection: SMCConnectionProtocol, @unchecked Sendable {
    var isOpen: Bool
    var keys: [String: (dataType: UInt32, bytes: [UInt8])]
    var writtenKeys: [(String, UInt32, [UInt8])] = []

    init(isOpen: Bool = true, keys: [String: (dataType: UInt32, bytes: [UInt8])] = [:]) {
        self.isOpen = isOpen
        self.keys = keys
    }

    func readKeyRaw(_ key: String) -> (dataType: UInt32, bytes: [UInt8])? {
        keys[key]
    }

    func writeKeyRaw(_ key: String, dataType: UInt32, bytes: [UInt8]) -> Bool {
        writtenKeys.append((key, dataType, bytes))
        return true
    }
}
