# Agent Instructions — symaira-tune

Native macOS tuning tool (Swift 6 toolchain, AppKit/IOKit). CLI **and** MCP
server: read the Mac's thermal/power/display state, and (incrementally) tune
brightness, fans, and battery charging. Public repo, MIT-licensed. Part of the
Symaira family — see `../AGENTS.md` / `../ECOSYSTEM.md` for cross-repo
conventions and `docs/commercial-boundary.md` for the public/pro boundary.

## Build & Test

```bash
swift build                # all targets
swift test                 # unit tests (no GUI / no hardware writes required)
swift run -q symtune doctor
```

Local toolchain note: if the Command Line Tools `swift` is broken (dyld errors),
build with the Xcode(-beta) toolchain:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
```

## Module Layout (SPM, dependency direction enforced by target deps)

```
symtune (executable)  →  SymTuneMCP  →  SymTuneCore
```

- `SymTuneCore` — all logic. Services (`SensorService`, `BatteryService`,
  `DisplayService`, `PowerService`, `SMCService`), models, config, errors, and
  `SafetyPolicy`. No MCP/CLI concerns here. Only target allowed to touch IOKit.
- `SymTuneMCP` — stdio JSON-RPC/MCP transport. Talks to `TuneController` only.
- `symtune` — thin CLI: arg routing, JSON output, `serve` wiring.

`TuneController` is the single facade. CLI and MCP never call services directly.

## Hard Rules

- **Safety first**: every write path (brightness, dim, fan, charge limit) MUST
  clamp through `SafetyPolicy` before applying, and MUST never disable firmware
  thermal protection. The controller is responsible for *restore-on-exit*: any
  overridden value resets to the system default when the process ends.
- **Honest capabilities**: never pretend a feature works. Unbuilt features throw
  `.notImplemented`; hardware/tier-gated ones throw `.unsupported`. `doctor`
  reports the truth per capability (`available` + `tier`).
- **Public/pro boundary**: no billing/tenant/cloud code here. SMC-write features
  (fan, charge limit) belong behind the privileged Pro helper — implement the
  core capability here first, then let the private repo consume it.
- **Zero stdout pollution in `serve`**: stdout carries only Content-Length-framed
  JSON-RPC frames. All logs/diagnostics go to stderr.
- **No third-party SPM dependencies** without a strong reason — system frameworks
  only, so the binary stays trivial to build, sign, and notarize.
- **JSON is snake_case**: encoders use `.convertToSnakeCase`. Keep Swift
  properties camelCase.

## Conventions (ecosystem)

- Binary: `symtune`. Paths: `~/.config/symtune/`, `~/.cache/symtune/`,
  `~/.local/share/symtune/` (see `ConfigPaths`). Env prefix: `SYMTUNE_*`.
- Exit codes: `0` ok · `1` error · `2` usage/config · `3` permission ·
  `4` unsupported/not-implemented (`ExitCode`).
- Distribution: notarized Direct/Homebrew cask (NOT the Mac App Store — fan/SMC
  and a global CLI are incompatible with the App Store sandbox).

## Roadmap pointers

`docs/roadmap.md` is the source of truth for what's built vs planned. v0.1 =
reads + keep-awake + MCP scaffold. v0.2 = EDR/extended brightness + dim overlay +
SMC sensor reads (needs a menu-bar/app context). Pro = privileged SMC helper for
fan curves & charge limiting. Tightening to Swift 6 strict concurrency is tracked
there too (v0.1 builds in Swift 5 language mode).
