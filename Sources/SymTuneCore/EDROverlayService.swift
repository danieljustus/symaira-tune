@preconcurrency import AppKit
import QuartzCore

/// Per-display EDR (Extended Dynamic Range) overlay. Creates a nearly invisible
/// on-screen layer with `wantsExtendedDynamicRangeContent = true` so that
/// Core Animation drives the display's peak brightness to the requested
/// headroom multiplier (1.0 = SDR, up to panel maximum, capped at 1.6).
///
/// This is the BrightIntosh approach: the overlay claims EDR headroom,
/// forcing the display to render brighter than its 100% SDR reference.
/// The layer is sized to cover the target display and accepts mouse events.
///
/// **Thread safety**: all window operations dispatch to `DispatchQueue.main`.
public final class EDROverlayService: @unchecked Sendable {
    /// Current EDR headroom per display (nil = no overlay active).
    nonisolated(unsafe) private var overlays: [CGDirectDisplayID: EDROverlay] = [:]
    private let lock = NSLock()

    public init() {}

    deinit {
        removeAllOverlays()
    }

    // MARK: - Public API

    /// Apply extended brightness to the built-in display.
    /// - Parameter multiplier: 1.0 = SDR reference, up to `SafetyPolicy.extendedBrightnessMax`.
    /// - Parameter displayID: target display; defaults to the built-in display.
    public func applyExtendedBrightness(
        _ multiplier: Double,
        displayID: CGDirectDisplayID? = nil
    ) throws {
        let targetID = try displayID ?? builtinDisplayID()

        guard multiplier >= SafetyPolicy.extendedBrightnessMin,
              multiplier <= SafetyPolicy.extendedBrightnessMax
        else {
            throw TuneError.usage(
                "Extended brightness must be between \(SafetyPolicy.extendedBrightnessMin) "
                + "and \(SafetyPolicy.extendedBrightnessMax)."
            )
        }

        let headroom = Float(multiplier)
        lock.lock()
        let existing = overlays[targetID]
        lock.unlock()

        if let overlay = existing {
            overlay.setHeadroom(headroom)
        } else {
            guard let screen = screenForDisplayID(targetID) else {
                throw TuneError.failed("Could not find screen for display \(targetID).")
            }
            let overlay = EDROverlay(displayID: targetID, screenFrame: screen.frame)
            overlay.setHeadroom(headroom)
            lock.lock()
            overlays[targetID] = overlay
            lock.unlock()
        }
    }

    /// Remove the EDR overlay for a specific display (restores SDR).
    public func removeOverlay(for displayID: CGDirectDisplayID) {
        lock.lock()
        let overlay = overlays.removeValue(forKey: displayID)
        lock.unlock()
        overlay?.removeFromScreen()
    }

    /// Remove all EDR overlays (full restore to SDR).
    public func removeAllOverlays() {
        lock.lock()
        let all = overlays
        overlays.removeAll()
        lock.unlock()
        for (_, overlay) in all {
            overlay.removeFromScreen()
        }
    }

    /// Current applied headroom for a display, or nil if no overlay.
    public func currentHeadroom(for displayID: CGDirectDisplayID) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return overlays[displayID].map { Double($0.headroom) }
    }

    /// The built-in display's current EDR headroom (from the system, not overlay).
    public func systemEDRHeadroom(for displayID: CGDirectDisplayID) -> Double? {
        guard let screen = screenForDisplayID(displayID) else { return nil }
        return Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
    }

    // MARK: - Private Helpers

    private func builtinDisplayID() throws -> CGDirectDisplayID {
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            if displayID != 0, CGDisplayIsBuiltin(displayID) != 0 {
                return CGDirectDisplayID(displayID)
            }
        }
        throw TuneError.unsupported("No built-in display detected for EDR overlay.")
    }

    private func screenForDisplayID(_ displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            if CGDirectDisplayID(id) == displayID {
                return screen
            }
        }
        return nil
    }
}

// MARK: - EDROverlay (internal)

/// A single on-screen EDR-capable overlay window for one display.
/// Uses a CAMetalLayer with `wantsExtendedDynamicRangeContent = true`
/// at the requested headroom level. The layer is nearly invisible
/// (very low alpha) so it doesn't affect visual content.
private final class EDROverlay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    private var window: NSWindow?
    private var metalLayer: CAMetalLayer?
    private(set) var headroom: Float = 1.0

    init(displayID: CGDirectDisplayID, screenFrame: NSRect) {
        self.displayID = displayID
        setupWindow(screenFrame: screenFrame)
    }

    func setHeadroom(_ value: Float) {
        headroom = value
        if Thread.isMainThread {
            updateHeadroom()
        } else {
            DispatchQueue.main.sync { [self] in updateHeadroom() }
        }
    }

    func removeFromScreen() {
        if Thread.isMainThread {
            doRemove()
        } else {
            DispatchQueue.main.sync { [self] in doRemove() }
        }
    }

    // MARK: - Private

    private func setupWindow(screenFrame: NSRect) {
        DispatchQueue.main.sync { [self] in
            MainActor.assumeIsolated {
                let window = NSWindow(
                    contentRect: screenFrame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )

                // Create a CAMetalLayer as the backing layer.
                let metalLayer = CAMetalLayer()
                metalLayer.frame = CGRect(origin: .zero, size: screenFrame.size)
                metalLayer.pixelFormat = MTLPixelFormat(rawValue: 80)!  // bgra10Unorm
                metalLayer.wantsExtendedDynamicRangeContent = true
                metalLayer.contentsFormat = .RGBA16Float
                metalLayer.contentsScale = window.backingScaleFactor

                // Start with no drawable content — the EDR headroom alone
                // drives the display brightness. Use a very dim white so
                // the layer is valid but nearly invisible.
                metalLayer.backgroundColor = NSColor(white: 0.01, alpha: 1.0).cgColor
                metalLayer.opacity = 1.0

                let contentView = NSView(frame: screenFrame)
                contentView.wantsLayer = true
                contentView.layer?.addSublayer(metalLayer)
                window.contentView = contentView

                // Window properties: invisible to user, passes through input.
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.level = .statusBar - 1  // Below menu bar, above most windows
                window.ignoresMouseEvents = true
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
                window.isReleasedWhenClosed = false
                window.orderFront(nil)

                self.window = window
                self.metalLayer = metalLayer
            }
        }
    }

    private func updateHeadroom() {
        MainActor.assumeIsolated {
            metalLayer?.setValue(headroom, forKey: "EDRHeadroom")
        }
    }

    private func doRemove() {
        MainActor.assumeIsolated {
            window?.orderOut(nil)
            window = nil
            metalLayer = nil
        }
    }
}
