# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — scaffold

Initial project scaffold. Buildable, tested, and runnable; read features and the
MCP server are functional, write features are stubbed honestly.

### Added
- SPM package with three targets: `SymTuneCore`, `SymTuneMCP`, `symtune`.
- CLI: `doctor`, `sensors`, `battery`, `displays`, `permissions`, `awake`,
  `serve`, `version`, `help`.
- Working reads: thermal pressure (`ProcessInfo`), battery health
  (`AppleSmartBattery` via IORegistry), display EDR headroom (`NSScreen`),
  keep-awake (IOKit power assertions).
- MCP server over stdio (JSON-RPC 2.0, Content-Length framing): `get_capabilities`,
  `get_sensors`, `get_battery`, `list_displays`, `keep_awake`, plus planned
  `set_extended_brightness` / `set_fan` / `set_charge_limit`.
- `SafetyPolicy` (clamping + thermal-protection guarantees) and typed
  `ExitCode` / `TuneError`.
- XDG path conventions (`ConfigPaths`), snake_case JSON output.
- Docs (README, AGENTS, architecture, roadmap, commercial-boundary), MIT license,
  SwiftLint config, Makefile, CI workflow.

### Not yet implemented (see docs/roadmap.md)
- SMC sensor reads (detailed temps / fan RPM).
- Extended/EDR brightness, software dim overlay, built-in brightness apply.
- Pro: privileged SMC helper for fan curves and battery charge limiting.
