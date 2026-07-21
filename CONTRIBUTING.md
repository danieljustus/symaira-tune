# Contributing to symtune

Thanks for your interest in contributing to symtune!

## Getting Started

1. **Clone the repo** and open in Xcode or build from the terminal:
   ```bash
   git clone https://github.com/danieljustus/symaira-tune.git
   cd symaira-tune
   swift build
   ```

2. **Run tests** to verify the baseline:
   ```bash
   swift test
   ```

3. **Run the CLI** to see it in action:
   ```bash
   swift run -q symtune doctor
   swift run -q symtune sensors
   ```

## Code Style

- Swift 6 toolchain, strict concurrency
- `swiftlint --strict` must pass
- JSON output uses snake_case (`.convertToSnakeCase`); Swift properties stay camelCase
- No third-party SPM dependencies — system frameworks only

## Pull Requests

1. Fork the repo and create a feature branch from `main`
2. Make your changes and ensure `swift build`, `swift test`, and `swiftlint` pass
3. Open a PR against `main` with a clear description of what changed and why
4. Include a safety acknowledgment if your changes touch privileged code paths (SMC writes, fan control, charge limits)

## Safety

symtune interacts with hardware (Apple SMC, display brightness, power management). All write paths are bounded by `SafetyPolicy`. If your PR touches any privileged code path:

- Verify restore-on-exit behavior
- Test on real hardware if possible
- Document any safety implications in the PR description

## Building the App

```bash
brew install xcodegen
make build-app
open build/app/SymairaTune.app
make smoke-app
```

## Questions?

Open a [Discussion](https://github.com/danieljustus/symaira-tune/discussions) if you have questions before starting work.
