@preconcurrency import AppKit

public final class DimOverlay: @unchecked Sendable {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var currentOpacity: Float = 1.0

    public init() {}

    deinit {
        for (_, window) in windows { window.close() }
    }

    public func applyDim(_ opacity: Float) {
        MainActor.assumeIsolated {
            currentOpacity = opacity
            let overlayAlpha = CGFloat(1.0 - opacity)

            for screen in NSScreen.screens {
                let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                guard displayID != 0 else { continue }

                if let existing = windows[CGDirectDisplayID(displayID)] {
                    existing.alphaValue = overlayAlpha
                    return
                }

                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                window.backgroundColor = NSColor.black
                window.alphaValue = overlayAlpha
                window.isOpaque = false
                window.hasShadow = false
                window.level = .screenSaver
                window.ignoresMouseEvents = true
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
                window.isReleasedWhenClosed = false
                windows[CGDirectDisplayID(displayID)] = window
                window.orderFront(nil)
            }
        }
    }

    public func removeAllOverlays() {
        MainActor.assumeIsolated {
            for (_, window) in windows { window.orderOut(nil) }
            windows.removeAll()
            currentOpacity = 1.0
        }
    }

    public var dimLevel: Float {
        MainActor.assumeIsolated { currentOpacity }
    }
}
