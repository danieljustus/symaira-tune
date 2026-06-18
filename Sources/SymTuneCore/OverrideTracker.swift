import Foundation
import IOKit
@preconcurrency import AppKit

/// Tracks applied display overrides and restores them on process exit.
/// Handles both normal exit (deinit) and abnormal signals (SIGINT/SIGTERM).
final class OverrideTracker: @unchecked Sendable {
    private var originalBrightness: Float?
    private var originalWarmth: Float?
    private var hasOverrides = false
    private var signalSources: [DispatchSourceSignal] = []

    func registerSignalHandlers() {
        let signals: [Int32] = [SIGINT, SIGTERM]
        for sig in signals {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.restoreAll()
                exit(ExitCode.ok.rawValue)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func saveBrightness(_ value: Float) {
        if originalBrightness == nil {
            originalBrightness = value
            hasOverrides = true
        }
    }

    func saveWarmth(_ value: Float) {
        if originalWarmth == nil {
            originalWarmth = value
            hasOverrides = true
        }
    }

    func restoreAll() {
        guard hasOverrides else { return }

        if let brightness = originalBrightness {
            restoreBrightness(brightness)
        }

        if originalWarmth != nil {
            if let displayID = builtinDisplayID() {
                CGDisplayRestoreColorSyncSettings()
                _ = displayID
            }
        }

        originalBrightness = nil
        originalWarmth = nil
        hasOverrides = false
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

    private func restoreBrightness(_ value: Float) {
        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            let info = IODisplayCreateInfoDictionary(service, UInt32(kIODisplayOnlyPreferredName)).takeRetainedValue() as? [String: Any]
            guard info?["DisplayVendorID"] != nil else {
                service = IOIteratorNext(iter)
                continue
            }
            let key = "brightness" as CFString
            IODisplaySetFloatParameter(service, 0, key, value)
            service = IOIteratorNext(iter)
        }
    }

    deinit {
        restoreAll()
    }
}
