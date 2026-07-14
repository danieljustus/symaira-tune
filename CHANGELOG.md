# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] — 2026-07-14

## [0.2.0] — 2026-07-13

### Added
- Standalone `SymairaTune.app` release packaging alongside the `symtune` CLI,
  including reproducible XcodeGen builds and bundle smoke checks (`#129`).
- Homebrew cask generation that installs the menu-bar app and links the CLI
  binary (`#129`).

## [0.1.4] — 2026-07-01

### Fixed
- Hardcoded tool version in `TuneVersion.current` is now synchronized with the release tag; release builds override it via `SYMTUNE_VERSION` so `symtune --version` matches the published release (`#112`).

### Added
- Release workflow verifies that the built binary reports the same version as the git tag before publishing the DMG (`#112`).

## [0.1.1] — 2026-06-23

### Fixed
- TuneConfig.load validates bounds against SafetyPolicy after parsing (`#72`).
- DimOverlay.deinit delegates to `removeAllOverlays()` for main-thread safety (`#73`).
- Dim overlay update continues for all displays in multi-monitor setups (`#74`).
- MCP transport rejects oversized Content-Length payloads (8 MB limit) (`#80`).
- MCP header overflow now throws instead of returning partial data (`#81`).
- EDR overlay no longer force-unwraps a raw MTLPixelFormat value (`#82`).
- `symtune version --check-for-updates` is non-blocking and writes to stderr (`#83`).
- Profiles no longer persist an unused `awake` field (`#84`).
- Unexpected CLI errors include full context, not just localizedDescription (`#85`).
- Restore-on-exit returns EDR to its prior headroom (`#86`).

### Changed
- MCP tool schemas include numeric bounds (`minimum`/`maximum`) (`#75`).
- MCPServer split into MCPTransport, MCPTool, MCPArguments, MCPTools (`#78`).
- UpdateChecker cache uses a private actor instead of `nonisolated(unsafe)` statics (`#77`).
- MCP transport hardens header parsing with proper terminator handling (`#89`).
- DisplayService extended brightness comment corrected (`#87`).
- Dead `TuneProfile.awake` field removed from model (`#88`).

## [0.1.0] — initial release

### Added
- Built-in display brightness get/set (`#20`).
- `config.toml` configuration file with `SYMTUNE_*` environment variable
  overrides (`#19`).
- Extended/EDR brightness, software dim overlay, warmth, restore-on-exit,
  profiles, and SMC sensor reads (`#49`). Fan curves, charge limiting, and
  DDC/CI are Pro-tier features (privileged helper required).
- Documentation sync for v0.1 feature set (`#65`).

### Fixed
- OverrideTracker signal handler: use `_exit()` instead of `exit()` to avoid
  re-entrant cleanup (`#48`).
- Orphan `SymairaTune` target moved to `docs/planned/` (`#66`).

### Security
- Profile name path traversal and 13 additional findings (`#35`).
- Security and correctness bugs from code review (`#63`).
- Restricted `GITHUB_TOKEN` permissions in CI workflows (`#67`).
