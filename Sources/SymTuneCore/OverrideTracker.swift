import Foundation
import IOKit
@preconcurrency import AppKit

/// Tracks applied display overrides and restores them on process exit.
/// Handles both normal exit (deinit) and abnormal signals (SIGINT/SIGTERM).
final class OverrideTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _originalBrightness: Float?
    private var _originalWarmth: Float?
    private var _appliedWarmth: Float = 0
    private var _originalEDRBrightness: Double?
    private var _hasOverrides = false
    private var signalSources: [DispatchSourceSignal] = []
    private var displayService: DisplayService?
    private var edrOverlay: EDROverlayService?

    var currentWarmth: Float {
        lock.lock()
        defer { lock.unlock() }
        return _appliedWarmth
    }

    init(displayService: DisplayService? = nil, edrOverlay: EDROverlayService? = nil) {
        self.displayService = displayService
        self.edrOverlay = edrOverlay
    }

    func registerSignalHandlers() {
        let signals: [Int32] = [SIGINT, SIGTERM]
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.restoreAll()
                _exit(ExitCode.ok.rawValue)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func saveBrightness(_ value: Float) {
        lock.lock()
        defer { lock.unlock() }
        if _originalBrightness == nil {
            _originalBrightness = value
            _hasOverrides = true
        }
    }

    func saveWarmth(_ value: Float) {
        lock.lock()
        defer { lock.unlock() }
        _appliedWarmth = value
        if _originalWarmth == nil {
            _originalWarmth = value
            _hasOverrides = true
        }
    }

    func saveEDRBrightness(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        if _originalEDRBrightness == nil {
            _originalEDRBrightness = value
            _hasOverrides = true
        }
    }

    func restoreAll() {
        lock.lock()
        let hasOverrides = _hasOverrides
        let brightness = _originalBrightness
        let warmth = _originalWarmth
        _originalBrightness = nil
        _originalWarmth = nil
        _originalEDRBrightness = nil
        _hasOverrides = false
        lock.unlock()

        guard hasOverrides else { return }

        if let brightness {
            restoreBrightness(brightness)
        }

        if warmth != nil {
            CGDisplayRestoreColorSyncSettings()
        }

        edrOverlay?.removeAllOverlays()
    }

    private func restoreBrightness(_ value: Float) {
        if let displayService {
            try? displayService.setBuiltinBrightness(value)
            return
        }

        guard let displayID = builtinDisplayID() else { return }

        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }

        let cgVendor = CGDisplayVendorNumber(displayID)
        let cgProduct = CGDisplayModelNumber(displayID)

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            let info = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any]
            guard let vendorID = info?["DisplayVendorID"] as? UInt32,
                  let productID = info?["DisplayProductID"] as? UInt32 else {
                service = IOIteratorNext(iter)
                continue
            }
            guard vendorID == cgVendor, productID == cgProduct else {
                service = IOIteratorNext(iter)
                continue
            }
            let key = "brightness" as CFString
            IODisplaySetFloatParameter(service, 0, key, value)
            return
        }
    }

    private func builtinDisplayID() -> CGDirectDisplayID? {
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            if displayID != 0, CGDisplayIsBuiltin(displayID) != 0 {
                return CGDirectDisplayID(displayID)
            }
        }
        return nil
    }

    deinit {
        restoreAll()
    }
}
