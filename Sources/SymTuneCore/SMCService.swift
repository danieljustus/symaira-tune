import Foundation
import IOKit

// MARK: - SMC Key Encoding

/// Encode a 4-character SMC key as a big-endian UInt32.
func smcEncodeKey(_ key: String) -> UInt32 {
    let utf8 = Array(key.utf8)
    guard utf8.count == 4 else { return 0 }
    return UInt32(utf8[0]) << 24 | UInt32(utf8[1]) << 16
         | UInt32(utf8[2]) << 8 | UInt32(utf8[3])
}

/// Decode a UInt32 SMC key back to a 4-character string.
func smcDecodeKey(_ value: UInt32) -> String {
    let b0 = UInt8((value >> 24) & 0xFF)
    let b1 = UInt8((value >> 16) & 0xFF)
    let b2 = UInt8((value >> 8) & 0xFF)
    let b3 = UInt8(value & 0xFF)
    return String(bytes: [b0, b1, b2, b3], encoding: .ascii) ?? "????"
}

// MARK: - SMC Value Conversion

/// Convert raw SMC bytes to a Double based on the data type.
func smcConvertValue(dataType: UInt32, bytes: [UInt8]) -> Double {
    let typeStr = smcDecodeKey(dataType)

    switch typeStr {
    case "fpe2":
        // Float with exponent bias 2 — standard for temperature sensors.
        // High byte = integer part, low byte = fractional part (1/256).
        guard bytes.count >= 2 else { return 0 }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 256.0

    case "flt ":
        // IEEE 754 float (4 bytes, big-endian).
        guard bytes.count >= 4 else { return 0 }
        let raw: UInt32 = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                        | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        var val: Float = 0
        memcpy(&val, withUnsafePointer(to: raw) { $0 }, MemoryLayout<Float>.size)
        return Double(val)

    case "sp78":
        // Signed fixed-point 7.8 (2 bytes, big-endian).
        guard bytes.count >= 2 else { return 0 }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0

    case "ui8 ":
        guard bytes.count >= 1 else { return 0 }
        return Double(bytes[0])

    case "ui16":
        guard bytes.count >= 2 else { return 0 }
        return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))

    case "ui32":
        guard bytes.count >= 4 else { return 0 }
        let raw: UInt32 = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                        | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        return Double(raw)

    default:
        // Unknown type: interpret as a big-endian unsigned integer.
        guard !bytes.isEmpty else { return 0 }
        var raw: UInt64 = 0
        for b in bytes { raw = (raw << 8) | UInt64(b) }
        return Double(raw)
    }
}

// MARK: - SMC Parameter Block

/// Raw 80-byte buffer matching the C `SMCParamStruct` layout used by the
/// AppleSMC IOKit driver. Fields are accessed via byte offsets derived from
/// the canonical C struct:
///
/// ```
/// offset  0: key            (UInt32)
/// offset  4: vers           (8 bytes — 4×UInt8 + UInt16 + UInt16)
/// offset 12: pLimitData     (16 bytes — 2×UInt16 + 3×UInt32, padded for alignment)
/// offset 28: keyInfo        (12 bytes — 2×UInt32 + UInt8 + 3 pad)
/// offset 40: result         (UInt8)
/// offset 41: status         (UInt8)
/// offset 42: data8          (UInt8)
/// offset 43: _pad           (1 byte)
/// offset 44: data32         (UInt32)
/// offset 48: bytes[32]      (32 bytes)
/// ```
struct SMCParamBlock: @unchecked Sendable {
    static let byteCount = 80

    var data: [UInt8]

    init() { data = [UInt8](repeating: 0, count: Self.byteCount) }

    // MARK: Key (bytes 0-3)

    var key: UInt32 {
        get { data.loadBE32(at: 0) }
        set { data.storeBE32(newValue, at: 0) }
    }

    // MARK: KeyInfo (bytes 28-39)

    var keyInfoDataSize: UInt32 {
        get { data.loadBE32(at: 28) }
        set { data.storeBE32(newValue, at: 28) }
    }

    var keyInfoDataType: UInt32 {
        get { data.loadBE32(at: 32) }
        set { data.storeBE32(newValue, at: 32) }
    }

    var keyInfoDataAttributes: UInt8 {
        get { data[36] }
        set { data[36] = newValue }
    }

    /// Copy the 12-byte keyInfo block (bytes 28-39) from another param block.
    mutating func copyKeyInfo(from other: SMCParamBlock) {
        for i in 28..<40 { data[i] = other.data[i] }
    }

    // MARK: Result / Status / data8 (bytes 40-42)

    var result: UInt8 { data[40] }
    var status: UInt8 { data[41] }

    var data8: UInt8 {
        get { data[42] }
        set { data[42] = newValue }
    }

    // MARK: data32 (bytes 44-47)

    var data32: UInt32 {
        get { data.loadBE32(at: 44) }
        set { data.storeBE32(newValue, at: 44) }
    }

    // MARK: Data bytes (bytes 48-79)

    /// Return the first `count` data bytes (max 32).
    func dataBytes(_ count: Int) -> [UInt8] {
        let n = min(Int(count), 32)
        guard n > 0 else { return [] }
        return Array(data[48 ..< 48 + n])
    }
}

// MARK: - UInt8 Array BE Helpers

private extension Array where Element == UInt8 {
    func loadBE32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
        | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }

    mutating func storeBE32(_ value: UInt32, at offset: Int) {
        self[offset]     = UInt8((value >> 24) & 0xFF)
        self[offset + 1] = UInt8((value >> 16) & 0xFF)
        self[offset + 2] = UInt8((value >> 8) & 0xFF)
        self[offset + 3] = UInt8(value & 0xFF)
    }
}

// MARK: - SMC Connection Holder

/// Reference-type wrapper for the IOKit `io_connect_t` handle.
/// Prevents accidental double-close when `SMCService` (a struct) is copied.
private final class SMCConnection: @unchecked Sendable {
    private static let taskPort: mach_port_t = mach_task_self_
    var handle: io_connect_t = IO_OBJECT_NULL
    var isOpen: Bool = false

    func open() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        let kr = IOServiceOpen(service, Self.taskPort, 0, &handle)
        guard kr == kIOReturnSuccess else { return false }

        // Probe: try reading a well-known key to confirm the driver works.
        var probe = SMCParamBlock()
        probe.key = smcEncodeKey("FNum")
        probe.data8 = 9 // READ_KEYINFO
        var out = SMCParamBlock()
        guard smcRawCall(handle: handle, input: &probe, output: &out) else {
            IOServiceClose(handle)
            handle = IO_OBJECT_NULL
            return false
        }

        isOpen = true
        return true
    }

    func close() {
        if handle != IO_OBJECT_NULL {
            IOServiceClose(handle)
            handle = IO_OBJECT_NULL
        }
        isOpen = false
    }

    deinit { close() }
}

// MARK: - Raw IOKit Call

/// Perform a single `IOConnectCallStructMethod` call on the SMC driver.
/// Selector 2 (`kSMCHandleYPCCommand`) is the standard command dispatch.
private func smcRawCall(
    handle: io_connect_t,
    input: inout SMCParamBlock,
    output: inout SMCParamBlock
) -> Bool {
    guard handle != IO_OBJECT_NULL else { return false }

    var outSize = SMCParamBlock.byteCount

    let kr = input.data.withUnsafeMutableBufferPointer { inBuf in
        output.data.withUnsafeMutableBufferPointer { outBuf in
            IOConnectCallStructMethod(
                handle,
                2, // kSMCHandleYPCCommand
                inBuf.baseAddress,
                SMCParamBlock.byteCount,
                outBuf.baseAddress,
                &outSize
            )
        }
    }

    return kr == kIOReturnSuccess
}

// MARK: - SMCService

/// Bridge to the System Management Controller (SMC) for temperature/fan sensors.
///
/// **Read-only** — fan/charge writes belong to the privileged Pro helper.
/// The connection is opened lazily on first use and closed on deinit.
/// All reads are unprivileged (user type 0).
///
/// Handles Apple Silicon vs Intel key differences automatically. Fanless Macs
/// are supported: `FNum` returning 0 produces an empty fans array.
public struct SMCService: Sendable {
    private let conn: SMCConnection

    public init() {
        conn = SMCConnection()
    }

    /// Whether the SMC bridge successfully connected to the AppleSMC driver.
    public var isAvailable: Bool { conn.isOpen }

    // MARK: - Key Reading

    /// Read an SMC key: returns the data type (as UInt32) and raw bytes,
    /// or nil if the key doesn't exist or the read fails.
    private func readKeyRaw(_ key: String) -> (UInt32, [UInt8])? {
        if !conn.isOpen { _ = conn.open() }
        guard conn.isOpen else { return nil }

        // Step 1: READ_KEYINFO — ask the driver for the key's type and size.
        var in1 = SMCParamBlock()
        in1.key = smcEncodeKey(key)
        in1.data8 = 9 // kSMCReadKeyInfo

        var out1 = SMCParamBlock()
        guard smcRawCall(handle: conn.handle, input: &in1, output: &out1),
              out1.result == 0
        else { return nil }

        let dataSize = out1.keyInfoDataSize
        let dataType = out1.keyInfoDataType
        guard dataSize > 0, dataSize <= 32 else { return nil }

        // Step 2: READ_KEY — fetch the actual value.
        var in2 = SMCParamBlock()
        in2.key = smcEncodeKey(key)
        in2.data8 = 5 // kSMCReadKey
        in2.copyKeyInfo(from: out1)

        var out2 = SMCParamBlock()
        guard smcRawCall(handle: conn.handle, input: &in2, output: &out2),
              out2.result == 0
        else { return nil }

        return (dataType, out2.dataBytes(Int(dataSize)))
    }

    /// Read an SMC key and convert to a Double.
    private func readKeyValue(_ key: String) -> Double? {
        guard let (dataType, bytes) = readKeyRaw(key) else { return nil }
        return smcConvertValue(dataType: dataType, bytes: bytes)
    }

    /// Read an SMC key as an unsigned integer (for `ui8 `, `ui16`, `ui32`).
    private func readKeyUInt(_ key: String) -> UInt? {
        guard let (_, bytes) = readKeyRaw(key), !bytes.isEmpty else { return nil }
        var result: UInt = 0
        for b in bytes { result = (result << 8) | UInt(b) }
        return result
    }

    // MARK: - Temperature Sensors

    public func readTemperatures() -> [SensorReading] {
        guard conn.isOpen else { return [] }

        #if arch(arm64)
        let keys = Self.appleSiliconTempKeys
        #else
        let keys = Self.intelTempKeys
        #endif

        var readings: [SensorReading] = []
        for (key, label) in keys {
            if let celsius = readKeyValue(key), celsius > 0 {
                readings.append(SensorReading(key: key, label: label, celsius: celsius))
            }
        }
        return readings
    }

    // MARK: - Fan Sensors

    public func readFans() -> [FanReading] {
        guard conn.isOpen else { return [] }

        // Fan count key (`FNum`) returns a ui8.
        guard let fanCount = readKeyUInt("FNum"), fanCount > 0 else { return [] }

        var fans: [FanReading] = []
        for i in 0..<min(fanCount, 4) { // practical max: 4 fans
            let prefix = "F\(i)"

            // Actual RPM: F0Ac, F1Ac, …
            guard let rpm = readKeyValue("\(prefix)Ac") else { continue }
            let rpmInt = Int(rpm)

            // Min / max RPM: best effort (may not exist on all Macs).
            let minRpm = readKeyValue("\(prefix)Mn").map(Int.init)
            let maxRpm = readKeyValue("\(prefix)Mx").map(Int.init)

            let label = i == 0 ? "Main Fan" : "Fan \(i + 1)"
            fans.append(FanReading(
                index: Int(i),
                label: label,
                rpm: rpmInt,
                minRpm: minRpm,
                maxRpm: maxRpm
            ))
        }
        return fans
    }

    // MARK: - Key Tables

    /// Apple Silicon (arm64) temperature sensor keys.
    /// Not all keys exist on every chip — missing keys are silently skipped.
    static let appleSiliconTempKeys: [(key: String, label: String)] = [
        ("Tp01", "CPU Core 1"),
        ("Tp02", "CPU Core 2"),
        ("Tp03", "CPU Core 3"),
        ("Tp04", "CPU Core 4"),
        ("Tp05", "CPU Core 5"),
        ("Tp06", "CPU Core 6"),
        ("Tp07", "CPU Core 7"),
        ("Tp08", "CPU Core 8"),
        ("Tp09", "CPU Core 9"),
        ("Tp10", "CPU Core 10"),
        ("Tp11", "CPU Core 11"),
        ("Tp12", "CPU Core 12"),
        ("TG0P", "GPU Die"),
        ("TM0P", "Memory Proximity"),
        ("Ts0S", "SoC Die"),
        ("Ta0P", "Ambient"),
    ]

    /// Intel (x86_64) temperature sensor keys.
    static let intelTempKeys: [(key: String, label: String)] = [
        ("TC0C", "CPU Core 1"),
        ("TC1C", "CPU Core 2"),
        ("TC2C", "CPU Core 3"),
        ("TC3C", "CPU Core 4"),
        ("TC4C", "CPU Core 5"),
        ("TC5C", "CPU Core 6"),
        ("TC6C", "CPU Core 7"),
        ("TC7C", "CPU Core 8"),
        ("TC8C", "CPU Core 9"),
        ("TC9C", "CPU Core 10"),
        ("TCXC", "CPU Core X"),
        ("TC0P", "CPU Proximity"),
        ("TG0P", "GPU Proximity"),
        ("TM0P", "Memory Proximity"),
        ("TA0P", "Ambient"),
    ]
}
