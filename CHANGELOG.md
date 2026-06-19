# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — initial release

### Added
- Built-in display brightness get/set (`#20`).
- `config.toml` configuration file with `SYMTUNE_*` environment variable
  overrides (`#19`).
- Extended/EDR brightness, software dim overlay, warmth, restore-on-exit,
  profiles, and SMC sensor reads (`#49`). Fan curves, charge limiting, and
  DDC/CI are Pro-tier features (privileged helper required).
- Documentation sync for v0.1 feature set (`#65`).

### Fixed
- OverrideTracker signal handler: use `_exit()` instead of `exit()` to avoid
  re-entrant cleanup (`#48`).
- Orphan `SymairaTune` target moved to `docs/planned/` (`#66`).

### Security
- Profile name path traversal and 13 additional findings (`#35`).
- Security and correctness bugs from code review (`#63`).
- Restricted `GITHUB_TOKEN` permissions in CI workflows (`#67`).
