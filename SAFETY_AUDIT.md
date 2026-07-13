# symtune Safety Model

This document describes the safety boundaries of the public `symtune` core as it
exists today. It is an implementation-grounded trust document, not a thermal
safety certification, a guarantee for every Mac model, or a promise about future
Pro functionality.

## Scope and status

`symtune` is a local macOS CLI and stdio MCP server for reading machine state and
applying display/power overrides. The public core currently implements these
write paths:

- built-in display brightness;
- extended/EDR brightness through an on-screen overlay;
- software dimming through an on-screen overlay;
- display warmth through a gamma LUT;
- keep-awake power assertions.

Fan writes and battery charge limiting are **not available in the public core**.
They are clamped and represented by a helper protocol, but calls return
`unsupported` until the separate privileged Pro helper is connected.

Relevant implementation:

- [`SafetyPolicy.swift`](Sources/SymTuneCore/SafetyPolicy.swift) — hard safety ranges and clamp primitive;
- [`Config.swift`](Sources/SymTuneCore/Config.swift) — user configuration bounded by those hard ranges;
- [`TuneController.swift`](Sources/SymTuneCore/TuneController.swift) — single write facade;
- [`OverrideTracker.swift`](Sources/SymTuneCore/OverrideTracker.swift) — display override capture and restoration;
- [`MCPTools.swift`](Sources/SymTuneMCP/MCPTools.swift) — MCP schemas and write-tool routing;
- [`SMCHelperProtocol.swift`](Sources/SymTuneCore/SMCHelperProtocol.swift) — public contract for the future privileged helper.

## Threat model

The safety model addresses:

1. **Malformed or extreme input** from a user, script, profile, or AI agent.
2. **An over-permissioned local MCP client** invoking a write tool without a
   human in the loop.
3. **Stale process state**, where a temporary display override would otherwise
   remain after `symtune` exits.
4. **Unsupported hardware or missing privileges**, where pretending that a
   capability worked would be more dangerous than refusing the request.
5. **Future privileged SMC writes**, which must not bypass the firmware's thermal
   control or write arbitrary values to hardware.

The model does **not** protect against a user who deliberately grants a hostile
process access to `symtune`, a compromised macOS host, kernel-level malware,
physical hardware faults, `SIGKILL`, a crash before cleanup, or power loss.

## Trust boundaries

### Local process boundary

`symtune` is a local process. It does not provide an authentication or
multi-user authorization layer for its CLI or stdio MCP server. The operating
system user and the process host are therefore part of the trust boundary.

Do not expose `symtune serve` through a network bridge unless that bridge adds
its own authentication, authorization, and audit controls. Stdio is transport,
not authorization.

### MCP boundary

The MCP server exposes both read and write tools. A connected MCP client can
request display changes, load a profile, keep the Mac awake, or call `restore`.
The server does not silently approve values outside the documented ranges:

- MCP schemas publish minimum and maximum values for numeric inputs;
- the controller clamps again before applying a write;
- unsupported Pro calls fail instead of being simulated.

The schema is only a client-facing contract. The controller is the enforcement
boundary. MCP transport and JSON-RPC wiring are implemented in
[`MCPServer.swift`](Sources/SymTuneMCP/MCPServer.swift); tool schemas and calls
are in [`MCPTools.swift`](Sources/SymTuneMCP/MCPTools.swift).

### Configuration boundary

`config.toml` and `SYMTUNE_*` variables may change configured limits, but they
cannot widen the hard limits in `SafetyPolicy`. Inverted or invalid ranges fall
back to defaults. Configuration is not a way to disable the safety policy.

## Write-path matrix

| Path | CLI / MCP entry point | Effective range | Current status | Restoration |
|---|---|---:|---|---|
| Built-in brightness | `brightness set` / `set_brightness` | `0.0–1.0` | Core, available when the display backend supports it | Original value is captured before the first successful override, then restored on normal teardown or `SIGINT`/`SIGTERM` when readable |
| Extended/EDR brightness | `extbright set` / `set_extended_brightness` | `1.0–1.6` | Core, display-dependent | Original system EDR headroom is captured best-effort; teardown restores it when available and removes overlays |
| Software dim | `dim set` / `set_dim` | `0.15–1.0` | Core | Overlay is removed during controller/service teardown; `dim reset` removes it explicitly |
| Warmth | `warmth set` / `set_warmth` | `0.0–1.0` | Core, display-dependent | System color-sync settings are restored during `restore` and teardown |
| Keep awake | `awake` / `keep_awake` | Boolean | Core | Power assertion is released when its token is ended; the MCP server holds at most one token |
| Fan control | `fan set` / `set_fan` | `0.0–1.0` fraction | Pro helper only; currently returns `unsupported` | Helper contract requires firmware-floor enforcement and restore on helper shutdown; no helper implementation is in this repo |
| Charge limit | `battery-limit set` / `set_charge_limit` | `50–100%` | Pro helper only; currently returns `unsupported` | Helper contract includes clearing the limit and restoring firmware defaults; no helper implementation is in this repo |

All numeric ranges are inclusive. The configured ranges are bounded again by
the constants in `SafetyPolicy`; the table describes the resulting hard limits,
not a promise that every display or Mac exposes every path.

## Guardrails by capability

### Display brightness

`TuneController.applyBuiltinBrightness` clamps through the configured range
(which cannot exceed the hard `SafetyPolicy` range), reads the current value,
and records the original value before applying the new value. A failed hardware
write is logged and propagated to the caller; it is not reported as successful.

### Extended/EDR brightness

EDR brightness is implemented as an on-screen layer, not as a firmware or SMC
write. The multiplier is limited to `1.0–1.6`. Before the first override,
`symtune` captures the system-reported EDR headroom when it can. Cleanup restores
that headroom when available and removes the overlay. If the system value cannot
be read, cleanup still removes the overlay, but an exact pre-existing headroom
value cannot be promised.

### Software dimming

Dimming uses a black, mouse-transparent overlay. The minimum opacity setting is
`0.15`, so the requested output cannot become fully black through this path.
`dim reset` removes all dim overlays and returns the tracked level to `1.0`.

### Warmth

Warmth uses a gamma LUT and is clamped to `0.0–1.0`. Reset uses
`CGDisplayRestoreColorSyncSettings`, returning the display to the system color
settings rather than trying to reconstruct a LUT manually.

### Fan and charge limiting

The public core does not connect a helper. `applyFan` and
`applyChargeLimit` clamp their inputs and then reject the request with
`TuneError.unsupported` when no helper is present. This is intentional: no public
core path writes fan or battery SMC keys today.

The helper contract in [`SMCHelperProtocol.swift`](Sources/SymTuneCore/SMCHelperProtocol.swift)
requires the future privileged implementation to:

- clamp again at the privileged boundary;
- preserve the firmware's automatic thermal curve as a floor;
- never disable firmware thermal protection;
- support clearing charge limits; and
- restore SMC overrides to firmware defaults during helper shutdown.

Those are requirements of the contract, not evidence that the private helper is
already implemented or independently audited here.

## Restore and failure behavior

`OverrideTracker` registers handlers for `SIGINT` and `SIGTERM`, restores tracked
display overrides, and exits. Normal object destruction also removes tracked
overrides and both overlay types.

The cleanup guarantee is therefore best-effort and applies to normal teardown
and the handled termination signals. It cannot cover `SIGKILL`, kernel panic,
process crash before cleanup, forced power-off, or hardware/OS failures during
restoration.

There is one current semantic limitation that callers must know:
`TuneController.restoreAll()` restores the tracker-backed brightness, warmth, and
EDR state, but does not currently call `resetDim()`. Use `dim reset` when the
process must remain running and the dim overlay should be removed immediately.
The dim overlay is still removed when the controller/service is torn down.

## What `symtune` will never do in the public core

The current core does not:

- write fan or charge-limit SMC keys without the privileged helper;
- accept an unbounded numeric value and pass it directly to a display or helper;
- claim that an unavailable or unimplemented capability succeeded;
- disable, replace, or silence firmware thermal protection;
- expose a network listener as part of `symtune serve`;
- store credentials, billing data, tenants, or cloud control-plane state;
- provide a guarantee that cleanup survives crashes, `SIGKILL`, or power loss.

A future helper or app must not weaken these boundaries. New write capabilities
require a corresponding controller path, hard range, tests, capability report,
MCP schema, and documentation update.

## Pro boundary

The public repository contains the core contract only. Privileged SMC writes
belong in the separate Pro helper, installed and managed through the macOS
privileged-service mechanism. The public/core repository must not grow billing,
tenant, cloud, or helper implementation code. See
[`docs/commercial-boundary.md`](docs/commercial-boundary.md) for the product
boundary and roadmap.

## Evidence and verification

The safety claims in this document are grounded in the current source and tests,
including:

- `SafetyPolicyTests` for clamping and the dim floor;
- `WriteSurfaceTests` for unsupported Pro paths and controller routing;
- `MCPServerToolSchemaTests` for published numeric bounds;
- `MCPServerToolCallTests` for unsupported Pro MCP calls and restore/dim calls;
- `SMCServiceTests` for bounded test-double SMC writes and unavailable hardware;
- `HardwareBackendIntegrationTests` for headless hardware-backend behavior.

Run the repository's standard checks before publishing changes:

```bash
swift build
swift test
swift run -q symtune doctor
```

This document must be updated whenever a new write path, helper integration,
restore behavior, or MCP tool changes the actual trust boundary.
