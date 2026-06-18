# Roadmap

Source of truth for what's built vs planned. Capability IDs match `doctor`.

## v0.1 — scaffold (current)

Buildable, tested, runnable. Reads + MCP work; writes are honest stubs.

- [x] SPM package, three targets, CI, docs, safety policy.
- [x] `sensors.thermalPressure` — coarse thermal level from `ProcessInfo`.
- [x] `battery.read` — `AppleSmartBattery` health (charge %, cycles, capacity).
- [x] `display.edr.read` — per-display EDR headroom.
- [x] `power.keepAwake` — IOKit power assertion (CLI `awake`, MCP `keep_awake`).
- [x] MCP server over stdio.

## v0.2 — core writes (no privileged helper)

The genuinely useful, low-risk, fast-to-ship layer.

- [ ] `sensors.smc` — AppleSMC IOKit bridge for die temps + fan RPM (read-only,
      unprivileged). Powers a real `sensors` output and a menu-bar readout.
- [ ] App/menu-bar target (xcodegen `project.yml`) — needed for on-screen EDR.
- [ ] `display.brightness.extended.set` — EDR/extended brightness (BrightIntosh
      approach: on-screen EDR layer). Clamped 1.0–1.6.
- [ ] `display.dim.set` — sub-minimum software dim overlay. Clamped ≥ 0.15.
- [ ] `display.brightness.set` — built-in brightness get/set.
- [ ] Color temperature / warmth (gamma) beyond Night Shift.
- [ ] Per-display profiles, hotkeys, simple rule engine
      (e.g. "on battery → cap brightness; on AC + hot → fan curve aggressive").
- [ ] Wire `config.toml` (`SYMTUNE_*` overrides) via `ConfigPaths`.
- [ ] Restore-on-exit for all applied display overrides.

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
- [ ] Update checker (GitHub releases), mirroring the ecosystem convention.
- [ ] Hardware-matrix notes: Apple Silicon vs Intel SMC keys, fanless MacBook Air.
