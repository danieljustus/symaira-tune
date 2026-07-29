## What's Changed

### Features
- #181 Keep-awake sessions with timer-based expiry, duration presets, display-sleep toggle, and remaining-time display. New CLI `symtune awake --for <duration>`, `--until HH:MM`, `status`, `off`. Extended MCP `keep_awake` tool and app Keep Awake card — closes #178
- #174 Integrate app update checking via `SymairaUpdateCheck` from symaira-appkit: non-blocking GitHub release check with skip-version persistence in the menu-bar app — closes #173
- #163 Add CI, release, and license badges to README — closes #157

### Fixes
- #180 Fix software dimming slider conversion between view dim amount and core brightness multiplier scale — closes #175
- #179 Fix fan control `restoreAuto()` to correctly throw `noFansDetected` when no fans are present; gate Fan Control card on fan availability — closes #176, closes #177

### Docs & Community
- #162 Add issue forms, PR template, CONTRIBUTING guide, and CODEOWNERS — closes #155, closes #156
- #161 Add SECURITY.md with vulnerability reporting policy — closes #152

### Internal
- #172 Extract EDROverlayServiceProtocol boundary and document hardware testability — closes #168
- #169 Cover TuneController error-logging paths and keep-awake/sensorsReport methods (line coverage 92.93% → 96.34%) — closes #164, closes #165
- #170 Cover MCP read-path and profile tool handlers — closes #166
- #171 Cover OverrideTracker active-query and signal-handler paths — closes #167

**Full Changelog**: https://github.com/danieljustus/symaira-tune/compare/v0.3.0...v0.4.0
