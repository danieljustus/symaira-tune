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
- `SensorService` — thermal pressure now (`ProcessInfo.thermalState`); detailed
  temps/fan RPM via `SMCService` later.
- `SMCService` — **stub** today. Future AppleSMC IOKit bridge for sensor reads
  (unprivileged) and, via the Pro helper, fan writes (privileged).
- `BatteryService` — reads `AppleSmartBattery` from the IORegistry (unprivileged;
  Intel + Apple Silicon notebooks).
- `DisplayService` — enumerates `NSScreen`s and reports EDR headroom (the signal
  that drives extended/>100% brightness). Read-only in v0.1.
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

Every capability is tagged `core` (this MIT binary) or `pro` (needs the
privileged SMC helper). `doctor` reports `available` + `tier` per capability so
callers never guess. Honesty rule: unbuilt → `.notImplemented`; hardware/tier
gated → `.unsupported`.

## Why some writes need an app or a helper

- **Extended/EDR brightness** and **sub-minimum dimming** require an on-screen
  EDR layer / overlay window, i.e. a GUI/menu-bar app context — not a bare CLI.
  These land with the app target (v0.2).
- **Fan control** and **charge limiting** require SMC *writes*, which need a
  privileged helper (`SMAppService`/`SMJobBless`) with a Developer ID. SMC
  *reads* are unprivileged and can ship in the core (v0.2).

## Distribution

Notarized direct download + Homebrew cask. The Mac App Store sandbox forbids SMC
access, DDC, and shipping a global CLI for agents.
