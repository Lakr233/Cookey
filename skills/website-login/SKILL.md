---
name: website-login
description: Use when the user needs to log in to a website and reuse that session locally as Playwright storageState JSON. You run Cookey CLI in your current environment; the user signs in on their iPhone in the Cookey app. End-to-end encrypted handoff via a relay. Use for MFA, SMS, passkeys, or flows that are hard to automate headlessly.
---

# Website login

**You** run the Cookey **CLI** in your current environment. The **user** completes the actual website login on **their iPhone** inside the Cookey app’s in-app browser—never on a browser you control remotely.

## How it works

Cookey splits “where login happens” from “where automation runs”:

1. **Local environment (`cookey` CLI + local daemon)** — You run commands here. The CLI creates a short-lived login request, agrees cryptographic keys with the phone, and waits for an encrypted payload. After delivery, you export **Playwright-compatible `storageState` JSON** (cookies + `origins` / localStorage) for local scripts.

2. **User’s iPhone (Cookey app)** — The user scans the QR or opens the deep link. The app opens the **target URL** in its **embedded browser**. The user signs in like a normal mobile session (password, OTP, authenticator app, passkeys, etc.). The app reads cookies and storage, **encrypts** them, and uploads **ciphertext** to the relay.

3. **Relay server** — Only moves opaque encrypted blobs and request metadata. It is **not** trusted with plaintext cookies or credentials; design assumes zero-knowledge transport.

4. **Result** — The CLI decrypts locally and writes session material under `~/.cookey/`. `cookey session export` strips Cookey-only metadata and outputs the same shape Playwright expects for `browser.newContext({ storageState })`.

**Why use this:** Many real sites are easier or only possible to log into on a **phone** (MFA apps, SMS, mobile-only UI). Cookey turns that authenticated mobile browser state into something **local Playwright** can load.

## Install

```sh
npm install -g @cookey/cli
# or
pip install cookey
```

Alternatively, download prebuilt binaries:

- macOS: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-macOS.zip
- Linux x86_64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-x86_64.zip
- Linux aarch64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-aarch64.zip

## What you export

`cookey session export` writes standard Playwright `storageState` JSON:

- `cookies`
- `origins`

Cookey keeps extra local metadata under `~/.cookey/`; `session export` strips
that and emits only what Playwright consumes.

## Quick workflow (you and the user)

1. **You** start a login request in your local environment:

   `cookey request start https://example.com/login --qr`

2. The **user** scans the QR (or opens the link) **on their iPhone** with the Cookey app, then finishes login in the app’s browser.

3. **You** export after the session is delivered:

   `cookey session export --latest --out storageState.json --pretty`

4. **You** (or the user’s code) load it in Playwright:

```ts
import { chromium } from "@playwright/test";

const browser = await chromium.launch();
const context = await browser.newContext({
  storageState: "storageState.json",
});
const page = await context.newPage();
await page.goto("https://example.com/account");
```

You can also pipe to a file:

`cookey session export r_xxxxxxxxxxxxxxxxxxxxxx > storageState.json`

## What you must show the user

When **you** start or refresh a Cookey request for the user, paste the **human-readable** strings from the CLI into your reply—not only a deep link.

- Always include the **pair key** as plain text.
- Always include the **CLI fingerprint / verification string** when the CLI prints it.
- You may add the deep link or jump link, but **never** as the only actionable content.

The Cookey app on **the user’s iPhone** may ask them to type the pair key and confirm the fingerprint matches the terminal.

## Important warning about `--attach`

Unless **your** tool-call environment keeps a detached process alive (e.g. `nohup`
or similar), do **not** use `--attach`. If the parent exits, verification can expire.

Default is detached: `cookey request start` / `cookey request refresh` spawns a **background daemon** and returns once the local descriptor exists. `--attach` blocks in the foreground until the session arrives.

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
  daemon PID. It also prints the CLI fingerprint / verification string when
  available.
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
  the descriptor status so **you** can tell `expired` from `error`.
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

## Suggested automation patterns (you)

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
