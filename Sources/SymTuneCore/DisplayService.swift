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
}
