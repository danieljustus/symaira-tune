import Foundation

/// XDG-style path resolution, matching the ecosystem convention
/// (`~/.config/sym{name}/`, `~/.cache/sym{name}/`, `~/.local/share/sym{name}/`).
/// Honors `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_DATA_HOME` overrides.
public struct ConfigPaths: Sendable {
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

    /// Load a `TuneConfig` from this path's `config.toml`, applying
    /// `SYMTUNE_*` environment overrides. Missing or malformed files
    /// silently fall back to defaults.
    public func loadConfig(
        env: [String: String] = ProcessInfo.processInfo.environment,
        parser: TOMLParser = TOMLParser()
    ) -> TuneConfig {
        TuneConfig.load(paths: self, env: env, parser: parser)
    }
}

// MARK: - TuneConfig

/// User-tunable configuration for symtune, loaded from `config.toml` with
/// `SYMTUNE_*` env overrides taking precedence over file values. Defaults
/// match `SafetyPolicy` constants.
public struct TuneConfig: Equatable, Sendable {
    public let extendedBrightnessMin: Double
    public let extendedBrightnessMax: Double
    public let dimMin: Double
    public let dimMax: Double
    public let brightnessMin: Double
    public let brightnessMax: Double
    public let fanFractionMin: Double
    public let fanFractionMax: Double
    public let chargeLimitMin: Int
    public let chargeLimitMax: Int
    public let defaultProfile: String

    public init(
        extendedBrightnessMin: Double = SafetyPolicy.extendedBrightnessMin,
        extendedBrightnessMax: Double = SafetyPolicy.extendedBrightnessMax,
        dimMin: Double = SafetyPolicy.dimMin,
        dimMax: Double = SafetyPolicy.dimMax,
        brightnessMin: Double = SafetyPolicy.brightnessMin,
        brightnessMax: Double = SafetyPolicy.brightnessMax,
        fanFractionMin: Double = SafetyPolicy.fanFractionMin,
        fanFractionMax: Double = SafetyPolicy.fanFractionMax,
        chargeLimitMin: Int = SafetyPolicy.chargeLimitMin,
        chargeLimitMax: Int = SafetyPolicy.chargeLimitMax,
        defaultProfile: String = "default"
    ) {
        self.extendedBrightnessMin = extendedBrightnessMin
        self.extendedBrightnessMax = extendedBrightnessMax
        self.dimMin = dimMin
        self.dimMax = dimMax
        self.brightnessMin = brightnessMin
        self.brightnessMax = brightnessMax
        self.fanFractionMin = fanFractionMin
        self.fanFractionMax = fanFractionMax
        self.chargeLimitMin = chargeLimitMin
        self.chargeLimitMax = chargeLimitMax
        self.defaultProfile = defaultProfile
    }

    // MARK: - Loading

    /// Load config from disk (if present) and apply env overrides.
    /// Missing file or parse errors silently return defaults.
    public static func load(
        paths: ConfigPaths = ConfigPaths(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        parser: TOMLParser = TOMLParser()
    ) -> TuneConfig {
        // Parse config file (empty table on missing / unreadable)
        var table = TOMLTable()
        if let data = try? Data(contentsOf: paths.configFile),
           let content = String(data: data, encoding: .utf8) {
            table = parser.parse(content)
        }

        // Helper: env override wins over TOML, then fallback
        func doubleVal(_ section: String, _ key: String,
                       _ envKey: String, _ fallback: Double) -> Double {
            if let raw = env[envKey], !raw.isEmpty, let d = Double(raw) { return d }
            if let val = table[section, key]?.doubleValue { return val }
            return fallback
        }
        func intVal(_ section: String, _ key: String,
                    _ envKey: String, _ fallback: Int) -> Int {
            if let raw = env[envKey], !raw.isEmpty, let i = Int(raw) { return i }
            if let val = table[section, key]?.intValue { return val }
            return fallback
        }
        func stringVal(_ section: String, _ key: String,
                       _ envKey: String, _ fallback: String) -> String {
            if let raw = env[envKey], !raw.isEmpty { return raw }
            if let val = table[section, key]?.stringValue { return val }
            return fallback
        }

        var config = TuneConfig(
            extendedBrightnessMin: doubleVal(
                "brightness", "extended_brightness_min",
                "SYMTUNE_EXTBRIGHT_MIN", SafetyPolicy.extendedBrightnessMin),
            extendedBrightnessMax: doubleVal(
                "brightness", "extended_brightness_max",
                "SYMTUNE_EXTBRIGHT_MAX", SafetyPolicy.extendedBrightnessMax),
            dimMin: doubleVal(
                "brightness", "dim_min",
                "SYMTUNE_DIM_MIN", SafetyPolicy.dimMin),
            dimMax: doubleVal(
                "brightness", "dim_max",
                "SYMTUNE_DIM_MAX", SafetyPolicy.dimMax),
            brightnessMin: doubleVal(
                "brightness", "brightness_min",
                "SYMTUNE_BRIGHTNESS_MIN", SafetyPolicy.brightnessMin),
            brightnessMax: doubleVal(
                "brightness", "brightness_max",
                "SYMTUNE_BRIGHTNESS_MAX", SafetyPolicy.brightnessMax),
            fanFractionMin: doubleVal(
                "fan", "fan_fraction_min",
                "SYMTUNE_FAN_MIN", SafetyPolicy.fanFractionMin),
            fanFractionMax: doubleVal(
                "fan", "fan_fraction_max",
                "SYMTUNE_FAN_MAX", SafetyPolicy.fanFractionMax),
            chargeLimitMin: intVal(
                "charge", "charge_limit_min",
                "SYMTUNE_CHARGE_MIN", SafetyPolicy.chargeLimitMin),
            chargeLimitMax: intVal(
                "charge", "charge_limit_max",
                "SYMTUNE_CHARGE_MAX", SafetyPolicy.chargeLimitMax),
            defaultProfile: stringVal(
                "general", "default_profile",
                "SYMTUNE_DEFAULT_PROFILE", "default")
        )

        // Clamp user-defined bounds to the non-negotiable SafetyPolicy hard limits.
        config = TuneConfig(
            extendedBrightnessMin: max(config.extendedBrightnessMin, SafetyPolicy.extendedBrightnessMin),
            extendedBrightnessMax: min(config.extendedBrightnessMax, SafetyPolicy.extendedBrightnessMax),
            dimMin: max(config.dimMin, SafetyPolicy.dimMin),
            dimMax: min(config.dimMax, SafetyPolicy.dimMax),
            brightnessMin: max(config.brightnessMin, SafetyPolicy.brightnessMin),
            brightnessMax: min(config.brightnessMax, SafetyPolicy.brightnessMax),
            fanFractionMin: max(config.fanFractionMin, SafetyPolicy.fanFractionMin),
            fanFractionMax: min(config.fanFractionMax, SafetyPolicy.fanFractionMax),
            chargeLimitMin: max(config.chargeLimitMin, SafetyPolicy.chargeLimitMin),
            chargeLimitMax: min(config.chargeLimitMax, SafetyPolicy.chargeLimitMax),
            defaultProfile: config.defaultProfile
        )

        // Validate min < max for each range; fall back to defaults on inversion.
        let rangesValid =
            config.extendedBrightnessMin < config.extendedBrightnessMax
            && config.dimMin < config.dimMax
            && config.brightnessMin < config.brightnessMax
            && config.fanFractionMin < config.fanFractionMax
            && config.chargeLimitMin < config.chargeLimitMax

        if !rangesValid {
            fputs("symtune: config error: inverted min/max range detected, falling back to defaults\n", stderr)
            config = TuneConfig()
        }

        return config
    }
}
