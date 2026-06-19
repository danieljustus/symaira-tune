# symaira-tune

> Tune your Mac — thermals, brightness, power — from the CLI and for AI agents.

`symtune` is a small, native macOS utility that reads your Mac's thermal, power,
and display state and (incrementally) lets you tune it: extended/EDR brightness,
software dimming, fan curves, and battery charge limits. Everything is exposed
**both** as a CLI and as an **MCP server**, so AI agents can observe and adjust
the machine — e.g. "this render is running hot, ramp the fans and dim the screen."

Part of the [Symaira](../ECOSYSTEM.md) family of AI-agent-native macOS tooling
(MIT core + optional Pro tier).

> **Status: v0.1 — core reads + writes.** Built-in brightness, extended/EDR
> brightness, software dim, color temperature warmth, profile management, and
> rule engine work today. Fan control and battery charge limiting need the Pro
> privileged helper. Not distributed yet.

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

## CLI

```text
symtune doctor                        # capabilities, host info, recommendations (JSON)
symtune sensors                       # thermal pressure + temps/fan RPM via AppleSMC (JSON)
symtune battery                       # charge %, cycles, capacity, health, condition (JSON)
symtune displays                      # displays + EDR headroom / extended-brightness capability
symtune permissions                   # permission & privileged-helper status
symtune awake [--display] [--seconds N]   # prevent idle sleep (like caffeinate)
symtune brightness get                # read built-in display brightness (0.0–1.0)
symtune brightness set <0.0-1.0>      # built-in display brightness
symtune extbright set <1.0-1.6>       # extended/EDR brightness via on-screen EDR layer
symtune dim set <0.15-1.0>            # software dim overlay
symtune dim reset                     # remove all dim overlays
symtune warmth set <0.0-1.0>          # color temperature warmth (gamma)
symtune warmth reset                  # reset warmth to neutral
symtune restore                       # restore all overrides to defaults
symtune profile save <name>           # save current settings as a profile
symtune profile load <name>           # apply a saved profile
symtune profile list                  # list saved profiles
symtune profile delete <name>         # delete a saved profile
symtune serve                         # run the MCP server over stdio

# Pro (needs privileged helper)
symtune fan set <0.0-1.0>            # fan speed fraction (Pro: needs helper)
symtune battery-limit set <50-100>   # hold charge at target percent (Pro: needs helper)
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
`set_warmth`, `reset_warmth`, `set_dim`, `reset_dim`, `restore`,
`save_profile`, `load_profile`, `list_profiles`, `delete_profile`, and the
Pro-tier `set_fan` / `set_charge_limit`.

## Safety

Every write path clamps through `SafetyPolicy` and never disables firmware
thermal protection; overridden values are restored when the process exits. See
`NOTICE` and `docs/architecture.md`.

## Documentation

- [docs/architecture.md](docs/architecture.md) — components & data flow
- [docs/roadmap.md](docs/roadmap.md) — built vs planned, by version/tier
- [docs/commercial-boundary.md](docs/commercial-boundary.md) — MIT core vs Pro helper
- [AGENTS.md](AGENTS.md) — contributor/agent guidance

## License

MIT © 2026 Daniel Justus. Inspired by Macs Fan Control and BrightIntosh (no code
from either).
