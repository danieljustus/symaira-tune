import Foundation
@testable import SymTuneCore

struct FakeSMCKeyResult {
    let dataType: UInt32
    let bytes: [UInt8]
}

struct FakeSMCWrittenKey {
    let key: String
    let dataType: UInt32
    let bytes: [UInt8]
}

final class FakeSMCConnection: SMCConnectionProtocol, @unchecked Sendable {
    var isOpen: Bool
    var keys: [String: FakeSMCKeyResult]
    var writtenKeys: [FakeSMCWrittenKey] = []

    init(isOpen: Bool = true, keys: [String: FakeSMCKeyResult] = [:]) {
        self.isOpen = isOpen
        self.keys = keys
    }

    func readKeyRaw(_ key: String) -> (dataType: UInt32, bytes: [UInt8])? {
        keys[key].map { ($0.dataType, $0.bytes) }
    }

    func writeKeyRaw(_ key: String, dataType: UInt32, bytes: [UInt8]) -> Bool {
        writtenKeys.append(FakeSMCWrittenKey(key: key, dataType: dataType, bytes: bytes))
        return true
    }
}
