# Roadmap

Source of truth for what's built vs planned. Capability IDs match `doctor`.

## v0.1 — core reads + writes (current)

Buildable, tested, runnable. Reads, writes, MCP, and profiles work today. Fan
and battery-charge writes need the Pro privileged helper.

- [x] SPM package, three targets, CI, docs, safety policy.
- [x] `sensors.thermalPressure` — coarse thermal level from `ProcessInfo`.
- [x] `sensors.smc` — AppleSMC IOKit bridge for die temps + fan RPM (unprivileged).
- [x] `battery.read` — `AppleSmartBattery` health (charge %, cycles, capacity).
- [x] `display.edr.read` — per-display EDR headroom.
- [x] `display.brightness.set` — built-in brightness get/set.
- [x] `display.brightness.extended.set` — EDR/extended brightness, clamped 1.0–1.6.
- [x] `display.dim.set` — sub-minimum software dim overlay, clamped ≥ 0.15.
- [x] `display.warmth.set` — color temperature warmth (gamma) beyond Night Shift.
- [x] `power.keepAwake` — IOKit power assertion (CLI `awake`, MCP `keep_awake`).
- [x] Profiles (save/load/list/delete) and simple rule engine.
- [x] Restore-on-exit for all applied display overrides.
- [x] Wire `config.toml` (`SYMTUNE_*` overrides) via `ConfigPaths`.
- [x] Update checker (GitHub releases).
- [x] MCP server over stdio.

## v0.2 — app / menu-bar target

The XcodeGen project and SwiftUI/AppKit sources exist under `Sources/SymTuneApp/` and `project.yml`, but the app target is not yet shipped as a first-class artifact. See [#129](https://github.com/danieljustus/symaira-tune/issues/129) for the shipping checklist.

- [x] XcodeGen project config (`project.yml`) and SwiftUI menu-bar app sources
- [x] CI build job for the app target
- [ ] Decide distribution: standalone DMG vs Symaira Hub integration
- [ ] Signed/notarized app artifact in releases
- [ ] Homebrew cask updated to install the app bundle
- [ ] End-to-end verification on macOS

## Pro — privileged SMC helper (separate repo, paid)

See `commercial-boundary.md`.

- [ ] Privileged helper via `SMAppService` (Developer ID, notarized).
- [ ] `fan.control` — fixed RPM + custom temperature→speed curves, presets
      (Quiet/Auto/Cool). Always honors the firmware floor.
- [ ] `battery.chargeLimit` — hold at target %, calibration/sailing modes.
- [ ] DDC/CI external-monitor brightness (IOKit I2C) — evaluate here vs helper.

## Cross-cutting / tech debt

- [ ] Tighten to Swift 6 strict concurrency (currently Swift 5 language mode;
      main friction is AppKit MainActor isolation in `DisplayService`).
- [ ] GoReleaser-equivalent release flow: notarized DMG + Homebrew cask in
      `../homebrew-tap` (mirror `symaira-terminal`).
- [ ] Hardware-matrix notes: Apple Silicon vs Intel SMC keys, fanless MacBook Air.
