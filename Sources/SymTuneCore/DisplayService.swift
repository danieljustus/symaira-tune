@preconcurrency import AppKit

/// Enumerates displays and reports EDR (Extended Dynamic Range) headroom, the
/// signal that drives extended/"brighter-than-100%" brightness on built-in XDR
/// and other HDR-capable panels.
///
/// v0.1 is read-only. Actually *applying* extended brightness needs an on-screen
/// EDR layer (a windowed/menu-bar app context), so the apply path is stubbed in
/// `TuneController` and lands with the app target in v0.2.
public struct DisplayService: Sendable {
    public init() {}

    // MARK: - Display enumeration

    public func list() -> DisplaysReport {
        var infos: [DisplayInfo] = []
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
            let isBuiltin = displayID != 0 ? (CGDisplayIsBuiltin(displayID) != 0) : nil

            infos.append(DisplayInfo(
                name: screen.localizedName,
                displayID: displayID,
                isBuiltin: isBuiltin,
                maxEDRHeadroom: screen.maximumExtendedDynamicRangeColorComponentValue,
                potentialEDRHeadroom: potential,
                edrCapable: potential > 1.0,
                backingScaleFactor: Double(screen.backingScaleFactor)
            ))
        }

        let notes: [String]
        if infos.isEmpty {
            notes = ["No displays reported — symtune must run inside a logged-in GUI session."]
        } else {
            notes = ["potential_edr_headroom > 1.0 means extended (>100%) brightness is possible on that display."]
        }
        return DisplaysReport(displays: infos, notes: notes)
    }

    /// Whether any attached display can provide extended brightness headroom.
    public func anyEDRCapable() -> Bool {
        NSScreen.screens.contains { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 }
    }

    // MARK: - Built-in brightness get/set

    /// Reads the built-in display brightness (0.0–1.0). Uses the DisplayServices
    /// private framework via dlopen (no link-time dependency), falling back to IOKit.
    public func getBuiltinBrightness() throws -> Double {
        let displayID = try builtinDisplayID()
        if let getBrightness = displayServicesGetBrightness {
            var brightness: Float = 0
            let result = getBrightness(displayID, &brightness)
            if result == 0 { return Double(brightness) }
        }
        return try iokitGetBrightness(displayID: displayID)
    }

    /// Sets the built-in display brightness (0.0–1.0). Caller must clamp via SafetyPolicy.
    public func setBuiltinBrightness(_ value: Float) throws {
        let displayID = try builtinDisplayID()
        if let setBrightness = displayServicesSetBrightness {
            let result = setBrightness(displayID, value)
            if result == 0 { return }
        }
        try iokitSetBrightness(displayID: displayID, value: value)
    }

    // MARK: - Warmth / color temperature

    /// Applies a warmth shift (0.0 = neutral, 1.0 = max warm) via gamma LUT
    /// manipulation using CGSetDisplayTransferByTable.
    public func applyWarmth(_ warmth: Float) throws {
        let steps = 256
        var redTable = [CGGammaValue](repeating: 0, count: steps)
        var greenTable = [CGGammaValue](repeating: 0, count: steps)
        var blueTable = [CGGammaValue](repeating: 0, count: steps)

        let redBoost: Float = 1.0
        let greenBoost: Float = 1.0 - warmth * 0.05
        let blueScale: Float = 1.0 - warmth * 0.30

        for i in 0..<steps {
            let normalized = Float(i) / Float(steps - 1)
            redTable[i] = min(normalized * redBoost, 1.0)
            greenTable[i] = min(normalized * greenBoost, 1.0)
            blueTable[i] = min(normalized * blueScale, 1.0)
        }

        let displayID = try builtinDisplayID()
        let result = CGSetDisplayTransferByTable(
            displayID, UInt32(steps), redTable, greenTable, blueTable
        )
        guard result == .success else {
            throw TuneError.failed("CGSetDisplayTransferByTable failed with code \(result.rawValue)")
        }
    }

    /// Resets the built-in display gamma to identity (no warmth shift).
    public func resetWarmth() throws {
        _ = try builtinDisplayID()
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Private helpers

    private func builtinDisplayID() throws -> CGDirectDisplayID {
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            if displayID != 0, CGDisplayIsBuiltin(displayID) != 0 {
                return CGDirectDisplayID(displayID)
            }
        }
        throw TuneError.unsupported("No built-in display detected.")
    }

    // MARK: - DisplayServices framework loading

    /// Dynamically loaded `DisplayServicesGetBrightness` function pointer.
    private nonisolated(unsafe) var displayServicesGetBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        )
        guard let handle else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
    }()

    /// Dynamically loaded `DisplayServicesSetBrightness` function pointer.
    private nonisolated(unsafe) var displayServicesSetBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)? = {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        )
        guard let handle else { return nil }
        guard let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
    }()

    // MARK: - IOKit fallback

    /// Read brightness via IOKit `IODisplayGetFloatParameter`.
    private func iokitGetBrightness(displayID: CGDirectDisplayID) throws -> Double {
        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard result == KERN_SUCCESS else {
            throw TuneError.failed("IOServiceGetMatchingServices failed: \(result)")
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }

            let status = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any]
            guard let vendorID = status?["DisplayVendorID"] as? UInt32,
                  let productID = status?["DisplayProductID"] as? UInt32 else {
                service = IOIteratorNext(iter)
                continue
            }

            let cgVendor = CGDisplayVendorNumber(displayID)
            let cgProduct = CGDisplayModelNumber(displayID)
            guard vendorID == cgVendor, productID == cgProduct else {
                service = IOIteratorNext(iter)
                continue
            }

            var brightness: Float = 0
            let key = "brightness" as CFString
            let status2 = IODisplayGetFloatParameter(service, 0, key, &brightness)
            if status2 == KERN_SUCCESS {
                return Double(brightness)
            }
            service = IOIteratorNext(iter)
        }

        throw TuneError.failed("Could not read brightness via IOKit for display \(displayID).")
    }

    private func iokitSetBrightness(displayID: CGDirectDisplayID, value: Float) throws {
        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard result == KERN_SUCCESS else {
            throw TuneError.failed("IOServiceGetMatchingServices failed: \(result)")
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }

            let info = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any]
            guard let vendorID = info?["DisplayVendorID"] as? UInt32,
                  let productID = info?["DisplayProductID"] as? UInt32 else {
                service = IOIteratorNext(iter)
                continue
            }

            let cgVendor = CGDisplayVendorNumber(displayID)
            let cgProduct = CGDisplayModelNumber(displayID)
            guard vendorID == cgVendor, productID == cgProduct else {
                service = IOIteratorNext(iter)
                continue
            }

            let key = "brightness" as CFString
            let status = IODisplaySetFloatParameter(service, 0, key, value)
            if status == KERN_SUCCESS { return }
            service = IOIteratorNext(iter)
        }

        throw TuneError.failed("Could not set brightness via IOKit for display \(displayID).")
    }
}
