# cookey

Cookey is a CLI-first tool for capturing an authenticated mobile browser session
and exporting it as Playwright-compatible `storageState` JSON.

## Install

- macOS: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-macOS.zip
- Linux x86_64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-x86_64.zip
- Linux aarch64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-aarch64.zip
- CLI documentation / skill file: https://github.com/Lakr233/Cookey/releases/latest/download/skills.md

## What Cookey Produces

`cookey session export` writes standard Playwright `storageState` JSON:

- `cookies`
- `origins`

Cookey keeps extra local metadata in its own session files under `~/.cookey/`,
but `session export` strips that metadata and emits only the Playwright-facing
payload.

## Quick Workflow

1. Start a login request:

   `cookey request start https://example.com/login --qr`

2. Scan the QR code with the Cookey iPhone app, then finish login in the app.

3. Export the delivered session:

   `cookey session export --latest --out storageState.json --pretty`

4. Use the file with Playwright:

```ts
import { chromium } from "@playwright/test";

const browser = await chromium.launch();
const context = await browser.newContext({
    storageState: "storageState.json",
});
const page = await context.newPage();
await page.goto("https://example.com/account");
```

You can also pipe directly to a file:

`cookey session export r_xxxxxxxxxxxxxxxxxxxxxx > storageState.json`

## Important Warning About `--attach`

Unless your tool call harness supports automatic process detach (e.g., `nohup`
or an init system), DO NOT use `--attach`. Without detach, the verification code
will expire when the parent process exits.

Default behavior is detached: `cookey request start` or `cookey request refresh`
launches a background daemon process and returns immediately after the local
descriptor is written. `--attach` keeps the current process alive and waits in
the foreground for session delivery.

## Command Reference

### `cookey request start <target_url>`

Create a new login request for `target_url`, register it with the relay, print
the pair key / deep link, and start a local waiter process.

Flags:

- `--server URL` override the relay server; must be `https://`
- `--timeout SECONDS` request lifetime in seconds; default `300`, capped at `1800`
- `--qr` render the `cookey://` deep link as a terminal QR code
- `--json` emit machine-readable JSON instead of human-readable output
- `--attach` wait inline instead of launching a detached daemon
- `--help` print command usage

Examples:

- `cookey request start https://example.com/login`
- `cookey request start https://example.com/login --qr`
- `cookey request start https://example.com/login --timeout 900 --server https://api.cookey.sh`
- `cookey request start https://example.com/login --json`

Notes:

- On success, the command prints a request ID (`rid`), pair key, jump link, and
  the daemon PID.
- Without `--attach`, the command exits as soon as the detached daemon is ready
  to wait for the encrypted session.

### `cookey request refresh <target_url>`

Create a refresh request for `target_url` using the latest local session for the
same target as seed state.

Flags:

- Same flags as `cookey request start`

Examples:

- `cookey request refresh https://example.com/login`
- `cookey request refresh https://example.com/login --qr`
- `cookey request refresh https://example.com/login --attach`

Notes:

- A previous local session for the same target is required. If none exists,
  Cookey returns: `no previous session found for this target; run cookey request start first`
- If the stored session contains device info, Cookey includes APNs metadata so
  the mobile app can be nudged directly.
- Refresh merges new cookies and local storage over the previously stored state,
  preserving missing values from the older session when needed.
- If the previous session does not contain device info, refresh still works, but
  the user must complete the flow from QR / pair key instead of push-assisted delivery.

### `cookey request status [rid]`

Inspect local request state. If there is no local record for the requested `rid`,
Cookey falls back to relay status using the configured default server.

Flags:

- `--latest` inspect the most recently updated local request or session
- `--watch` poll once per second until a terminal state is reached
- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey request status`
- `cookey request status r_xxxxxxxxxxxxxxxxxxxxxx`
- `cookey request status --latest`
- `cookey request status --latest --watch`
- `cookey request status r_xxxxxxxxxxxxxxxxxxxxxx --json`

Status values:

- `waiting` daemon is alive and waiting for the encrypted session
- `receiving` session arrived and is being decrypted / written locally
- `ready` session file exists and is exportable
- `expired` request lifetime ended before a usable session was written
- `orphaned` daemon descriptor says the request was active, but the daemon process is gone
- `error` the daemon failed while waiting, decrypting, or writing
- `missing` no local or remote record was found

Notes:

- `cookey request status` with no `rid` and no `--latest` returns a summary of
  the latest daemon and latest session.
- `--watch` requires either an explicit `rid` or `--latest`.

### `cookey session export [rid]`

Export a local session as Playwright `storageState` JSON.

Flags:

- `--latest` export the newest local session
- `--out FILE` write to `FILE` instead of stdout
- `--pretty` pretty-print JSON with indentation
- `--help` print command usage

Examples:

- `cookey session export --latest > storageState.json`
- `cookey session export --latest --out storageState.json --pretty`
- `cookey session export r_xxxxxxxxxxxxxxxxxxxxxx`

Notes:

- If `--out` is relative, it is resolved against the current working directory.
- If the session file is missing but a daemon descriptor exists, Cookey reports
  the descriptor status so you can distinguish `expired` and `error` cases.
- The exported file is suitable for Playwright's `browser.newContext({ storageState })`.

### `cookey session list`

List all locally known request IDs, newest first, using the newest timestamp from
either the daemon descriptor or the exported session file.

Flags:

- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey session list`
- `cookey session list --json`

### `cookey session delete <rid>`

Delete the local session file and daemon descriptor for `rid`.

Flags:

- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey session delete r_xxxxxxxxxxxxxxxxxxxxxx`
- `cookey session delete r_xxxxxxxxxxxxxxxxxxxxxx --json`

Notes:

- Cookey refuses to delete an active request whose daemon is still in `waiting`
  or `receiving` state.

### `cookey session clean`

Delete all inactive local request/session pairs.

Flags:

- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey session clean`
- `cookey session clean --json`

Notes:

- Active requests are skipped instead of force-killed.

### `cookey config get [key]`

Read configured defaults from `~/.cookey/config.json`.

Supported keys:

- `default-server`
- `timeout-seconds`
- `session-retention-days`

Aliases:

- `server` -> `default-server`
- `timeout` -> `timeout-seconds`
- `retention-days` -> `session-retention-days`

Flags:

- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey config get`
- `cookey config get default-server`
- `cookey config get timeout --json`

### `cookey config set <key> <value>`

Persist configured defaults in `~/.cookey/config.json`.

Flags:

- `--json` emit machine-readable JSON
- `--help` print command usage

Examples:

- `cookey config set default-server https://api.cookey.sh`
- `cookey config set timeout-seconds 900`
- `cookey config set retention-days 30 --json`

Notes:

- `default-server` must parse as a relay base URL and must use `https`.
- `timeout-seconds` must be a positive integer.
- `session-retention-days` is stored in config today, but the current CLI does
  not automatically delete sessions based on that value. Use `session clean` for
  explicit cleanup.

## Additional Behavior Details

- Every CLI entry point bootstraps `~/.cookey/`, ensures the keypair exists,
  ensures device ID exists, and cleans up stale daemon descriptors.
- Request/session JSON under `~/.cookey/` is written atomically.
- User-facing commands return exit code `0` on success and `1` on CLI/validation errors.
- Inline daemon execution used by `--attach` can also return:
  - `3` when the request expires before session delivery
  - `5` when the daemon encounters a relay, decrypt, or local write failure

## Suggested Automation Patterns

Detached start + watch:

```sh
cookey request start https://example.com/login --qr
cookey request status --latest --watch
cookey session export --latest --out storageState.json --pretty
```

JSON-first scripting:

```sh
cookey request start https://example.com/login --json
cookey request status --latest --json
cookey session export --latest --out storageState.json
```

Playwright usage:

```ts
import { chromium } from "@playwright/test";

const browser = await chromium.launch();
const context = await browser.newContext({
    storageState: "storageState.json",
});
```
