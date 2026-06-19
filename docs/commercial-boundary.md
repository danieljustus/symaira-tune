# Commercial Boundary — Core vs Pro

`symaira-tune` follows the ecosystem pattern: an open **MIT core** plus an
optional **Pro** layer for the capabilities that need privileged hardware access.

## Core (this repo, MIT)

Everything that is unprivileged or app-local:

- Read state: thermal pressure, battery health, display/EDR info.
- Keep-awake (power assertions).
- Display tuning that needs only an app context (not the SMC):
  extended/EDR brightness, software dim overlay, built-in brightness (v0.1).
- The full CLI surface and the MCP server.

No billing, tenant, account, or cloud code lives here.

## Pro (separate, privileged helper)

Capabilities that require **SMC writes**, and therefore a privileged helper
installed via `SMAppService`/`SMJobBless` with a Developer ID:

- Fan control: fixed RPM and custom temperature→speed curves.
- Battery charge limiting: hold at a target percent, calibration/sailing modes.

Rationale for keeping these behind a paid helper:

- They carry real hardware-safety/liability weight — they deserve a maintained,
  signed, notarized helper with strong guardrails (clamp ranges, never disable
  thermal protection, restore-on-exit).
- They map cleanly to a Pro tier and the existing Symaira "Suite" bundle pricing.

## Implementation rule

Implement the **core capability** in this repo first (e.g. the SMC bridge and
sensor reads), release/tag it, then let the private Pro repo/helper consume the
tagged artifact. Never add Pro-only/cloud code to this repo.
