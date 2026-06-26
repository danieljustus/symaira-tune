# symaira-tune Architecture

## Overview

`symtune` is a local macOS tuning tool for humans and AI agents. It exposes the
Mac's thermal/power/display state as JSON over a CLI and as MCP tools, and
(incrementally) lets callers adjust brightness, fans, and battery charging.

Design split (mirrors the rest of the Symaira family):

```
symtune (executable)  →  SymTuneMCP  →  SymTuneCore
```

- The agent/user decides *what* to do.
- `symtune` reads deterministic environment state and performs bounded actions.
- The transport for agents is local MCP over stdio.

## Components

### `SymTuneCore`

The only target with logic or IOKit access.

- `TuneController` — facade. CLI and MCP talk to this and nothing else. Holds the
  services, applies `SafetyPolicy`, and owns restore-on-exit bookkeeping.
- `SensorService` — thermal pressure (`ProcessInfo.thermalState`) and, when
  available, detailed temps/fan RPM via `SMCService`.
- `SMCService` — AppleSMC IOKit bridge for sensor reads (die temps, fan RPM;
  unprivileged) and, via the Pro helper, fan writes (privileged).
- `BatteryService` — reads `AppleSmartBattery` from the IORegistry (unprivileged;
  Intel + Apple Silicon notebooks).
- `DisplayService` — enumerates `NSScreen`s, reports EDR headroom (the signal
  that drives extended/>100% brightness), gets/sets built-in display brightness,
  applies gamma-based color temperature warmth, and resets gamma to neutral.
- `PowerService` — IOKit power assertions (keep-awake), the `caffeinate` analog.
- `SafetyPolicy` — clamping ranges and the thermal-protection guarantee.
- `Models` / `Errors` / `ExitCode` / `Config` / `Version` — DTOs and conventions.

### `SymTuneMCP`

- Minimal stdio JSON-RPC/MCP transport with Content-Length framing.
- `initialize`, `tools/list`, `tools/call`, `ping`.
- One place for tool schemas + argument validation. Holds at most one keep-awake
  assertion for the server's lifetime.

### `symtune` (CLI)

- Argument routing, JSON emission (`.convertToSnakeCase`, pretty), `serve` wiring,
  and the blocking `awake` loop.

## Capability tiers

Every capability is tagged `core` (this Apache-2.0 binary) or `pro` (needs the
privileged SMC helper). `doctor` reports `available` + `tier` per capability so
callers never guess. Honesty rule: unbuilt → `.notImplemented`; hardware/tier
gated → `.unsupported`.

## Why some writes need an app or a helper

- **Extended/EDR brightness**, **sub-minimum dimming**, **built-in brightness**,
  and **color temperature warmth** use on-screen EDR layers, overlay windows, and
  gamma LUTs. These work from the CLI today — no app target needed.
- **Fan control** and **charge limiting** require SMC *writes*, which need a
  privileged helper (`SMAppService`/`SMJobBless`) with a Developer ID. SMC
  *reads* are unprivileged and ship in the core.

## Distribution

Notarized direct download + Homebrew cask. The Mac App Store sandbox forbids SMC
access, DDC, and shipping a global CLI for agents.
