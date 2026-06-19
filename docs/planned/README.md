# Planned Features (v0.2+)

These files contain service implementations that are not yet wired into the
main `TuneController` facade. They are kept here for reference and will be
integrated when the corresponding features are ready.

## Files

### SymairaTune/ (AppDelegate.swift, StatusBarController.swift, Info.plist)
Menu-bar application for `symaira-tune`. A status-bar-only `LSUIElement` app
(no dock icon) that surfaces sensor/battery/display reports in a dropdown
menu. The `xcodegen` `project.yml` and generated `SymairaTune.xcodeproj` are
the canonical build path for this target — it is not wired into `Package.swift`
because SPM does not produce a real macOS `.app` bundle.

**Planned for:** v0.2 menu-bar app per `docs/roadmap.md`. The
`StatusBarController` is functional but uses a fragile menu-swap pattern and
lacks `do/catch` around `TuneController` calls — those refinements land with
the v0.2 wiring.

### DDCService.swift
DDC/CI (Display Data Channel Command Interface) service for controlling
external monitor brightness, contrast, and input selection. Requires I2C
access via IOKit, which needs a C bridging header for proper Swift access.

**Planned for:** External monitor brightness/contrast control via DDC/CI.

### BatteryLimitService.swift
Battery charge limit service with SMC key detection (Apple Silicon vs Intel)
and validation. The actual SMC writes go through `SMCHelperProtocol`.

**Planned for:** Battery charge limiting (Pro tier feature).

### FanControlModels.swift
Fan preset models (`FanPreset`) and temperature→speed curves (`FanCurve`)
with built-in presets (quiet, balanced, aggressive).

**Planned for:** Custom fan curves and preset-based fan control.

## Integration Path

When ready to integrate:
1. Move files back to `Sources/SymTuneCore/` (or to `Sources/SymairaTune/` for
   the menu-bar app, paired with a new executable target in `Package.swift`
   *or* a properly built `.app` bundle from the existing `project.yml`).
2. Wire into `TuneController` with stub/unsupported behavior (matching the
   pattern of `applyFan`/`applyChargeLimit`)
3. Update capabilities report to reflect available features
4. Add CLI commands for the new features

## Notes

- These files compile but contribute nothing to the shipped product
- They were moved here to reduce confusion for contributors
- The `TuneController` already has `applyFan` and `applyChargeLimit` methods
  that use `SMCHelperProtocol` directly — these services provide an
  alternative architecture that may be adopted in the future
