# symaira-tune

> Tune your Mac — thermals, brightness, power — from the CLI and for AI agents.

`symtune` is a small, native macOS utility that reads your Mac's thermal, power,
and display state and lets you tune it: extended/EDR brightness, software dimming,
**fan speed**, and **battery charge limits**. Everything is exposed **both** as a
CLI and as an **MCP server**, so AI agents can observe and adjust the machine —
e.g. "this render is running hot, ramp the fans and dim the screen."

Part of the [Symaira](../ECOSYSTEM.md) family of AI-agent-native macOS tooling
(Apache-2.0).

> **Status: v0.3 core + standalone menu-bar app.** The current release includes
> fan control and battery charge limiting directly in the open core. SMC writes
> require `sudo`. Homebrew installs both the app and the CLI from the generated
> cask (`brew install danieljustus/tap/symtune`).

## Why not the Mac App Store?

Fan/SMC control, DDC, and shipping a global `symtune` CLI for agents are
incompatible with the App Store sandbox. `symtune` is built for **notarized
direct distribution / Homebrew cask** (the same channel as `symaira-terminal`).

## Install (from source)

```bash
git clone <repo-url> && cd symaira-tune
swift build -c release
.build/release/symtune doctor
```

## Standalone menu-bar app

The app is a first-class standalone artifact, not a Hub-only component. From a
macOS checkout with full Xcode and XcodeGen installed:

```bash
brew install xcodegen
make build-app
open build/app/SymairaTune.app
make smoke-app
```

The release DMG contains `SymairaTune.app` and the CLI binary. The app uses the
same `TuneController` and `SafetyPolicy` as the CLI and MCP surfaces. See
[`docs/manual-app-verification.md`](docs/manual-app-verification.md) for the
real-host control and restore-on-exit checklist.

## CLI

```text
symtune doctor                        # capabilities, host info, recommendations (JSON)
symtune sensors                       # thermal pressure + temps/fan RPM via AppleSMC (JSON)
symtune battery                       # charge %, cycles, capacity, health, condition (JSON)
symtune displays                      # displays + EDR headroom / extended-brightness capability
symtune permissions                   # permission & SMC write status
symtune awake [--display] [--seconds N]   # prevent idle sleep (like caffeinate)
symtune brightness get                # read built-in display brightness (0.0–1.0)
symtune brightness set <0.0-1.0>      # built-in display brightness
symtune extbright set <1.0-1.6>       # extended/EDR brightness via on-screen EDR layer
symtune dim set <0.15-1.0>            # software dim overlay
symtune dim reset                     # remove all dim overlays
symtune warmth set <0.0-1.0>          # color temperature warmth (gamma)
symtune warmth reset                  # reset warmth to neutral
symtune fan set <0.0-1.0>             # fan speed fraction (requires sudo)
symtune fan auto                      # return fans to firmware automatic control
symtune battery-limit set <50-100>    # hold charge at target percent (requires sudo)
symtune battery-limit clear           # re-enable charging (requires sudo)
symtune restore                       # restore all overrides to defaults
symtune profile save <name>           # save current settings as a profile
symtune profile load <name>           # apply a saved profile
symtune profile list                  # list saved profiles
symtune profile delete <name>         # delete a saved profile
symtune serve                         # run the MCP server over stdio
```

Example:

```bash
$ symtune battery
{
  "current_capacity_percent": 82,
  "cycle_count": 93,
  "health_percent": 97,
  "present": true,
  "temperature_celsius": 30.6,
  ...
}

$ sudo symtune fan set 0.5
$ sudo symtune battery-limit set 80
```

## MCP integration

Register `symtune serve` with any MCP-capable agent host (Claude Desktop, Cursor,
OpenCode, …). Example fragment:

```json
{
  "mcpServers": {
    "symtune": {
      "command": "/absolute/path/to/symtune",
      "args": ["serve"]
    }
  }
}
```

Tools exposed: `get_capabilities`, `get_sensors`, `get_battery`, `list_displays`,
`keep_awake`, `get_brightness`, `set_brightness`, `set_extended_brightness`,
`set_warmth`, `reset_warmth`, `set_dim`, `reset_dim`, `set_fan`,
`set_charge_limit`, `clear_charge_limit`, `restore`, `save_profile`,
`load_profile`, `list_profiles`, `delete_profile`, `get_status`, `get_history`.

## Safety

Every active write path is bounded by `SafetyPolicy`. Fan and charge-limit
commands write to the Apple SMC and require `sudo`; they are clamped to safe
ranges, never disable firmware thermal protection, and restore the original SMC
values on normal teardown or `SIGINT`/`SIGTERM`. Temporary display overrides are
restored in the same way. Read the full, implementation-grounded model in
[`SAFETY_AUDIT.md`](SAFETY_AUDIT.md). See also [`NOTICE`](NOTICE) and
[`docs/commercial-boundary.md`](docs/commercial-boundary.md).

## License

Apache-2.0 © 2026 Daniel Justus. Inspired by Macs Fan Control and BrightIntosh (no code
from either).
