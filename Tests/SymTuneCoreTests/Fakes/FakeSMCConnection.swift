import Foundation
@testable import SymTuneCore

struct FakeSMCKeyResult {
    let dataType: UInt32
    let bytes: [UInt8]
}

final class FakeSMCConnection: SMCConnectionProtocol, @unchecked Sendable {
    var isOpen: Bool
    var keys: [String: FakeSMCKeyResult]
    var writtenKeys: [(String, UInt32, [UInt8])] = []

    init(isOpen: Bool = true, keys: [String: FakeSMCKeyResult] = [:]) {
        self.isOpen = isOpen
        self.keys = keys
    }

    func readKeyRaw(_ key: String) -> (dataType: UInt32, bytes: [UInt8])? {
        keys[key].map { ($0.dataType, $0.bytes) }
    }

    func writeKeyRaw(_ key: String, dataType: UInt32, bytes: [UInt8]) -> Bool {
        writtenKeys.append((key, dataType, bytes))
        return true
    }
}
