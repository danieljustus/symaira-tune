# symaira-tune

> Tune your Mac — thermals, brightness, power — from the CLI and for AI agents.

`symtune` is a small, native macOS utility that reads your Mac's thermal, power,
and display state and (incrementally) lets you tune it: extended/EDR brightness,
software dimming, fan curves, and battery charge limits. Everything is exposed
**both** as a CLI and as an **MCP server**, so AI agents can observe and adjust
the machine — e.g. "this render is running hot, ramp the fans and dim the screen."

Part of the [Symaira](../ECOSYSTEM.md) family of AI-agent-native macOS tooling
(MIT core + optional Pro tier).

> **Status: v0.1 scaffold.** Read features and the MCP server work today. Write
> features (brightness/dim/fan/charge) are stubbed with honest errors and land
> per `docs/roadmap.md`. Not distributed yet.

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
symtune doctor          # capabilities, host info, recommendations (JSON)
symtune sensors         # thermal pressure + (planned) temps/fan RPM (JSON)
symtune battery         # charge %, cycles, capacity, health, condition (JSON)
symtune displays        # displays + EDR headroom / extended-brightness capability
symtune permissions     # permission & privileged-helper status
symtune awake [--display] [--seconds N]   # prevent idle sleep (like caffeinate)
symtune serve           # run the MCP server over stdio

# planned / Pro (return an honest error in v0.1)
symtune extbright set 1.4         # extended/EDR brightness (planned v0.2)
symtune dim set 0.5               # software dim overlay     (planned v0.2)
symtune fan set 0.6               # fan speed fraction        (Pro: needs helper)
symtune battery-limit set 80      # hold charge at %          (Pro: needs helper)
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
`keep_awake`, and the planned `set_extended_brightness` / `set_fan` /
`set_charge_limit`.

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
