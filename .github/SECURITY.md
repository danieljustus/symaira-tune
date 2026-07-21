# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| v0.3.x  | ✅        |
| < 0.3   | ❌        |

Only the latest release receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in `symtune`, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, use one of these channels:

1. **GitHub Private Vulnerability Reporting** (preferred): Use the "Report a vulnerability" button on the [Security tab](https://github.com/danieljustus/symaira-tune/security).
2. **Email**: Contact the maintainer at the address listed on the [GitHub profile](https://github.com/danieljustus).

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected version
- Any potential impact assessment

### What to expect

- Acknowledgment within 48 hours
- A fix timeline once the issue is confirmed
- Credit in the release notes (unless you prefer to remain anonymous)

## Scope

`symaira-tune` interacts with hardware (Apple SMC, display brightness, power management) and runs with elevated privileges for certain features. Vulnerabilities in these privileged code paths are particularly sensitive.

## Safety

Every write path (brightness, dim, fan, charge limit) is bounded by `SafetyPolicy`. Fan and charge-limit commands require `sudo`. The tool restores original values on normal teardown or signal. See [SAFETY_AUDIT.md](../SAFETY_AUDIT.md) for the full safety model.
