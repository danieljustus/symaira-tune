import Foundation

/// XDG-style path resolution, matching the ecosystem convention
/// (`~/.config/sym{name}/`, `~/.cache/sym{name}/`, `~/.local/share/sym{name}/`).
/// Honors `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` overrides.
///
/// NOTE: TOML parsing of `config.toml` and `SYMTUNE_*` env overrides are not
/// wired yet (v0.1 has no user-tunable persisted settings). This type fixes the
/// path layout now so later versions stay consistent. See docs/roadmap.md.
public struct ConfigPaths {
    public let configDir: URL
    public let cacheDir: URL
    public let dataDir: URL

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        func base(_ envKey: String, _ fallback: String) -> URL {
            if let value = env[envKey], !value.isEmpty {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        self.configDir = base("XDG_CONFIG_HOME", ".config")
            .appendingPathComponent("symtune", isDirectory: true)
        self.cacheDir = base("XDG_CACHE_HOME", ".cache")
            .appendingPathComponent("symtune", isDirectory: true)
        self.dataDir = base("XDG_DATA_HOME", ".local/share")
            .appendingPathComponent("symtune", isDirectory: true)
    }

    public var configFile: URL { configDir.appendingPathComponent("config.toml") }
}
