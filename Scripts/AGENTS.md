# Scripts

Build, signing, and CI automation scripts for the Cookey CLI release pipeline.

## Files

| Script | Purpose |
|--------|---------|
| `build-release.sh` | Full release workflow: universal binary build, code signing, zip packaging, Apple notarization |
| `setup-ci-keychain.sh` | Restores signing keychain from CI secrets, detects signing identity and notarytool profile |

## How They Work Together

`build-release.sh` calls `setup-ci-keychain.sh` to initialize signing credentials before code signing.

### build-release.sh stages

`build-cli` → `package-cli` → `sign-cli` → `notarize-cli` (or `all` for sequential)

Options: `--tag`, `--archive-root`, `--stage`, `--keychain-profile`, `--skip-notarize`

### setup-ci-keychain.sh

Outputs environment variables: `KEYCHAIN_PATH`, `KEYCHAIN_PROFILE`, `SIGNING_IDENTITY`, `SIGNING_IDENTITY_NAME`, `SIGNING_IDENTITY_HASH`, `DEVELOPMENT_TEAM`

## Shell Conventions

- `set -euo pipefail` — strict error handling
- `#!/bin/zsh` shebang
- Logging: `log()` with `==>` prefix, `log_kv()` for key-value pairs
- Temporary files via `mktemp` with trap-based cleanup
- Secrets loaded from environment, never logged or hardcoded
- Keychain state captured and restored on exit
