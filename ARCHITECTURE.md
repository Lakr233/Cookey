# Cookey Architecture

## 1. Goals

Cookey is not a general-purpose authentication system. It is a minimal, self-hostable, CLI-first tool for scanning a QR code on mobile, logging in to a target website, and delivering the resulting browser session back to the local terminal.

Core constraints:

- No APNs dependency. No device registration flow.
- Zero-knowledge relay. The server only forwards encrypted session data.
- In-memory storage by default. Optional long-polling or WebSocket transport.
- Single session payload capped at 1 MB.
- CLI local state is minimal but must be recoverable, inspectable, and exportable.

---

## 2. Components

The system has three parts:

1. **CLI** — runs on the user's terminal. Generates the identity keypair, publishes the public key, waits for the session, decrypts it, and writes it to disk.

2. **Mobile App** — after scanning the QR code, opens the target website in an in-app browser, extracts cookies and `localStorage`, encrypts the session with the CLI's public key, and uploads it to the relay.

3. **Relay Server** — stores only short-lived metadata and the encrypted session blob. Never interprets plaintext session content. Never persists to a database.

Trust boundaries:

- The user trusts their local CLI machine.
- The user trusts their own mobile device.
- The relay server is untrusted.

---

## 3. Local Directory Layout

All CLI state lives under `~/.cookey/`:

```text
~/.cookey/
├── keypair.json
├── config.json
├── sessions/
│   └── {rid}.json
└── daemons/
    └── {rid}.json
```

Permission requirements:

- `~/.cookey/` — `0700`
- `keypair.json` — `0600`
- `sessions/*.json` — `0600`
- `daemons/*.json` — `0600`

### 3.1 keypair.json

A long-term identity keypair is generated on first run and saved to `~/.cookey/keypair.json`:

```json
{
  "version": 1,
  "algorithm": "ed25519",
  "public_key": "base64...",
  "private_key": "base64...",
  "created_at": "2026-03-28T12:00:00Z"
}
```

Notes:

- This stores the CLI's long-term `ed25519` identity key.
- At session encryption time, the runtime converts this key to an `x25519` key for ECDH.
- This way only one stable identity file is needed locally; no per-`login` private key persistence is required.

### 3.2 config.json

Optional configuration file:

```json
{
  "default_server": "https://relay.example.com",
  "transport": "ws",
  "timeout_seconds": 300,
  "session_retention_days": 7
}
```

### 3.3 daemons/{rid}.json

Descriptor file for a background waiting process:

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "pid": 43127,
  "ppid": 1,
  "status": "waiting",
  "server_url": "https://relay.example.com",
  "transport": "ws",
  "started_at": "2026-03-28T12:01:03Z",
  "updated_at": "2026-03-28T12:01:03Z",
  "target_url": "https://example.com/login"
}
```

---

## 4. CLI Bootstrap

Every CLI entry point runs the same bootstrap sequence:

1. Create `~/.cookey/` with permissions `0700`.
2. Check whether `~/.cookey/keypair.json` exists.
3. If not, generate an `ed25519` keypair and write it to `~/.cookey/keypair.json`.
4. Generate the device fingerprint.
5. Create `~/.cookey/sessions/`.
6. Create `~/.cookey/daemons/`.
7. Read `config.json` and load defaults for server, transport, and timeout.
8. Clean up obviously stale daemon descriptors (e.g. PID no longer exists but status is still `waiting`).

### 4.1 Device Fingerprint

The device fingerprint is used for diagnostics, auditing, and multi-device differentiation. It is not used in the encryption flow and must not be treated as an authentication factor.

Recommended inputs:

- `public_key`
- `hostname`
- `os`
- `arch`
- `machine-id` when available

Recommended algorithm:

```text
fingerprint = base64url(sha256(public_key || hostname || os || arch || machine_id))
```

Requirements:

- The fingerprint must be stable but does not need to be secret.
- When `machine-id` is unavailable, fall back to `public_key + hostname + os + arch`.
- The fingerprint is included in the login manifest and written to session metadata.

---

## 5. login Command

`login` is the main entry point. It initiates a new session-receive flow.

```bash
cookey login <target_url> [--server URL] [--timeout 300] [--transport ws|poll] [--json] [--no-detach]
```

### 5.1 Responsibilities

When `cookey login` is run, the CLI must:

1. Run bootstrap.
2. Generate a new request ID (`rid`).
3. Read the local `ed25519` public key and derive the `x25519` public key for this session.
4. Build the login manifest.
5. Register the manifest with the relay server.
6. Output a QR code, deep link, or manually-typeable short code.
7. Fork a child process to wait for the session in the background.
8. Exit the parent process immediately.

### 5.2 rid Generation

`rid` must be high-entropy and unpredictable:

- 128-bit random value
- Encoded with `base62` or `base32 crockford`
- 20–26 characters long

Example:

```text
r_8GQx8tY0j8x3Yw2N
```

### 5.3 Login Manifest

Metadata sent by the CLI to the relay when registering a pending request:

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "server_url": "https://relay.example.com",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "transport_hint": "ws",
  "created_at": "2026-03-28T12:01:03Z",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

Notes:

- `target_url` may be embedded directly in the QR code or kept only as short-lived server-side metadata.
- `cli_public_key` is the recipient public key the mobile app uses to encrypt the session.
- `device_fingerprint` identifies which CLI device the request originated from.

### 5.4 User-Visible Output

`login` must output at minimum:

- `rid`
- `target_url`
- `server_url`
- QR code content
- Deep link or manually-typeable code
- Background daemon PID

Recommended QR code content:

```text
cookey://login?rid=<rid>&server=<server_url>&target=<target_url>&pubkey=<cli_public_key>
```

### 5.5 Parent Process Behaviour

The parent process is only responsible for initiating the request and handing off control:

1. Complete bootstrap.
2. Generate and register the pending request.
3. Fork the child process.
4. Confirm the child PID has been written to `~/.cookey/daemons/{rid}.json`.
5. Print `rid` and PID.
6. Exit with code `0`.

If fork, registration, or PID file write fails, the parent must exit with a non-zero code.

---

## 6. Background Process fork/detach

This is the core execution model for `login`.

### 6.1 Process Model

Requirements:

- The parent process exits immediately after forking.
- The child process calls `setsid()` to detach from the controlling terminal.
- The child process closes or redirects stdio.
- The child process enters a background wait for the session.
- The child PID is written to `~/.cookey/daemons/`.

Recommended flow:

```text
CLI parent
  -> fork()
  -> child PID known
  -> wait until ~/.cookey/daemons/{rid}.json is durable
  -> print rid / pid
  -> exit(0)

CLI child
  -> setsid()
  -> redirect stdio
  -> write daemon descriptor
  -> connect to server
  -> wait for encrypted session
  -> decrypt
  -> write ~/.cookey/sessions/{rid}.json
  -> update daemon status=ready
  -> exit(0)
```

### 6.2 Daemon Descriptor Semantics

`~/.cookey/daemons/{rid}.json` is not a log file — it is a state receipt.

Allowed `status` values:

- `waiting`
- `receiving`
- `ready`
- `expired`
- `error`

State transition rules:

- Write `waiting` immediately on startup.
- Write `receiving` when a server push has been received but not yet flushed to disk.
- Write `ready` after `sessions/{rid}.json` has been atomically written.
- Write `expired` on timeout.
- Write `error` on any failure.

### 6.3 Transport

The background child process waits for the session using one of two transports:

1. **WebSocket** — connect to `GET /v1/requests/{rid}/ws` and wait for server-pushed status and encrypted payload.
2. **Long polling** — loop on `GET /v1/requests/{rid}/wait?timeout=30` until `ready`, `expired`, or a timeout is returned.

Requirements:

- WebSocket is preferred.
- Long polling is the compatibility fallback.
- Both transports must return the same final payload structure.

### 6.4 Local Processing After Session Receipt

After the background child receives the encrypted session:

1. Validate `rid`, version, and payload size.
2. Decrypt the session using the local private key.
3. Verify the decrypted result contains valid Playwright `cookies` and `origins`.
4. Atomically write the session to `~/.cookey/sessions/{rid}.json`.
5. Update daemon status to `ready`.
6. Delete the consumed encrypted payload from the relay, or confirm the server has already deleted it.

Atomic write requirements:

- Write to `~/.cookey/sessions/{rid}.json.tmp`.
- `fsync`.
- `rename` to the final filename.

### 6.5 Timeout and Exit

The child process lifetime matches `login --timeout` (default 300 seconds).

Exit codes:

- `0` — session successfully written to disk.
- `3` — request expired.
- `4` — network errors exhausted all retries.
- `5` — decryption or format validation failed.

---

## 7. status Command

`status` queries the current state of a request or session.

```bash
cookey status [rid] [--latest] [--watch] [--json]
```

### 7.1 Behaviour

If `rid` is provided:

1. Check whether `~/.cookey/sessions/{rid}.json` exists.
2. If it does, status is `ready`.
3. Otherwise check `~/.cookey/daemons/{rid}.json`.
4. If the daemon file exists, check whether the PID is still alive.
5. Query the server for remote status if needed.

If `rid` is not provided:

- Show a summary of the most recent pending daemon and ready sessions.

### 7.2 Status Values

| Status      | Meaning                                                             |
| ----------- | ------------------------------------------------------------------- |
| `waiting`   | Daemon started, waiting for mobile upload                           |
| `receiving` | Server payload received; decrypting or writing to disk              |
| `ready`     | Local session file exists                                           |
| `expired`   | Request expired; no session received                                |
| `orphaned`  | Daemon descriptor exists but PID is gone and session does not exist |
| `error`     | Background process failed                                           |
| `missing`   | Not found locally or on the server                                  |

### 7.3 Watch Mode

`cookey status <rid> --watch` replaces manual polling.

Behaviour:

- Refresh local state every 1–2 seconds.
- If transport is WebSocket, subscribe to server status directly.
- Exit when status reaches `ready`, `expired`, or `error`.

### 7.4 Machine-Readable Output

`--json` output:

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "status": "ready",
  "pid": 43127,
  "target_url": "https://example.com/login",
  "session_path": "/home/user/.cookey/sessions/r_8GQx8tY0j8x3Yw2N.json",
  "updated_at": "2026-03-28T12:02:19Z"
}
```

---

## 8. export Command

`export` writes the local session as a Playwright-ready `storageState` file, or dumps the full raw envelope.

```bash
cookey export <rid> [--format playwright|raw] [--out FILE|-] [--pretty]
```

### 8.1 Default Behaviour

Default format is `playwright`:

- Read `~/.cookey/sessions/{rid}.json`.
- Output only top-level `cookies` and `origins`.
- Strip `_cookey` metadata.

Default output filename:

```text
./storage-state.<rid>.json
```

### 8.2 Raw Behaviour

`--format raw` exports the full session JSON, including:

- Playwright-compatible session body.
- Cookey metadata.
- Origin, timestamps, device fingerprint, server info.

### 8.3 Playwright Integration

The exported `playwright` file can be used directly:

```ts
import { chromium } from "@playwright/test";

const browser = await chromium.launch();
const context = await browser.newContext({
  storageState: "./storage-state.r_8GQx8tY0j8x3Yw2N.json",
});
```

### 8.4 Failure Conditions

Non-zero exit code when:

- No session found for the given `rid`.
- Session JSON is malformed.
- `cookies` or `origins` fields are missing.
- Output path is not writable.

---

## 9. Session JSON Format

Local session files are stored at:

```text
~/.cookey/sessions/{rid}.json
```

The file must be Playwright-compatible. Recommended format: Playwright top-level structure plus a `_cookey` metadata namespace:

```json
{
  "cookies": [
    {
      "name": "sessionid",
      "value": "abc123",
      "domain": ".example.com",
      "path": "/",
      "expires": 1775068800,
      "httpOnly": true,
      "secure": true,
      "sameSite": "Lax"
    }
  ],
  "origins": [
    {
      "origin": "https://example.com",
      "localStorage": [
        { "name": "authToken", "value": "secret-token" },
        { "name": "theme", "value": "dark" }
      ]
    }
  ],
  "_cookey": {
    "version": 1,
    "rid": "r_8GQx8tY0j8x3Yw2N",
    "server_url": "https://relay.example.com",
    "target_url": "https://example.com/login",
    "device_fingerprint": "base64url-sha256",
    "transport": "ws",
    "captured_at": "2026-03-28T12:02:18Z",
    "received_at": "2026-03-28T12:02:19Z",
    "user_agent": "Mozilla/5.0 (...)",
    "source": "ios"
  }
}
```

### 9.1 Compatibility Rules

- `cookies` and `origins` must match the Playwright `storageState` structure exactly.
- All Cookey-specific metadata must be placed under `_cookey` to avoid conflicting with Playwright fields.
- `export --format playwright` must strip `_cookey`.

### 9.2 Field Constraints

| Field                        | Requirement                              |
| ---------------------------- | ---------------------------------------- |
| `cookies`                    | Array; may be empty; must be present     |
| `origins`                    | Array; may be empty; must be present     |
| `_cookey.version`            | Integer; currently `1`                   |
| `_cookey.rid`                | Must match the filename                  |
| `_cookey.device_fingerprint` | Generated during bootstrap               |
| `_cookey.captured_at`        | Timestamp when mobile finished capturing |
| `_cookey.received_at`        | Timestamp when CLI wrote the file        |

---

## 10. CLI Command Reference

### 10.1 login

```bash
cookey login <target_url> [--server URL] [--timeout SEC] [--transport ws|poll] [--json] [--no-detach]
```

Creates a new login-receive request, starts a background daemon to wait for the session, and outputs the `rid`, QR code, and daemon PID.

### 10.2 status

```bash
cookey status [rid] [--latest] [--watch] [--json]
```

Queries the status of a specific `rid`, or shows a summary of recent requests.

### 10.3 export

```bash
cookey export <rid> [--format playwright|raw] [--out FILE|-] [--pretty]
```

Exports a Playwright `storageState` file, or the full raw local session.

### 10.4 list

```bash
cookey list [--sessions] [--daemons] [--state waiting|ready|expired|error] [--json]
```

Lists local session files and/or daemon descriptors, with optional state filtering. Default: show both sessions and daemons.

### 10.5 rm

```bash
cookey rm <rid> [--kill] [--force]
cookey rm --expired
cookey rm --all
```

Deletes a local session file and/or daemon descriptor. `--kill` terminates a still-running daemon. Without `--force`, running daemons are not deleted.

### 10.6 config

```bash
cookey config get <key>
cookey config set <key> <value>
cookey config list
```

Supported keys: `default_server`, `transport`, `timeout_seconds`, `session_retention_days`.

### 10.7 server

```bash
cookey server [--listen 0.0.0.0:8080] [--public-url URL] [--ttl 300] [--max-payload 1048576]
```

Starts a self-hosted relay server with in-memory storage. Default TTL: 300 s. Default max payload: 1 MB. Supports WebSocket and long polling.

---

## 11. Relay Server Protocol

The server protocol handles exactly three things:

1. Register a pending request.
2. Accept an encrypted session upload from mobile.
3. Deliver the encrypted session to the waiting CLI daemon.

### 11.1 API

#### `POST /v1/requests`

Register a pending request.

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

#### `GET /v1/requests/{rid}`

Query whether the request exists and its current status.

#### `GET /v1/requests/{rid}/ws`

CLI daemon connects via WebSocket to wait for status changes and session delivery.

#### `GET /v1/requests/{rid}/wait?timeout=30`

CLI daemon long-polls for the session.

#### `POST /v1/requests/{rid}/session`

Mobile uploads the encrypted session.

```json
{
  "version": 1,
  "algorithm": "x25519-xsalsa20poly1305",
  "ephemeral_public_key": "base64...",
  "nonce": "base64...",
  "ciphertext": "base64...",
  "captured_at": "2026-03-28T12:02:18Z"
}
```

### 11.2 Server Storage Constraints

The server stores only:

- Pending request metadata.
- The encrypted session payload.
- Expiry timestamps.

The server never stores:

- Plaintext cookies.
- Plaintext `localStorage`.
- CLI private keys.
- User passwords.

### 11.3 Delivery Semantics

One-upload, one-delivery model:

- After a successful mobile upload the server transitions status to `ready`.
- After the CLI daemon successfully receives the payload, the server immediately deletes the encrypted session.
- If not consumed before TTL, the session is automatically deleted.

---

## 12. Security and Implementation Constraints

### 12.1 Encryption Model

Recommended model:

- CLI stores a long-term `ed25519` identity key.
- At runtime, convert to `x25519` for ECDH.
- Mobile generates an ephemeral `x25519` keypair per upload.
- Encrypt the session payload with the ECDH shared secret.

This achieves:

- Stable CLI identity.
- Per-upload forward secrecy.
- Server-side zero knowledge.

### 12.2 Plaintext Storage Boundary

Only the local CLI machine may store plaintext sessions, and only at:

```text
~/.cookey/sessions/{rid}.json
```

The server must never store plaintext.

### 12.3 Fault Tolerance

- If a daemon descriptor is corrupt, `status` must return `error` or `orphaned`; it must not fail silently.
- If writing the session file fails, the daemon status must not be updated to `ready`.
- `export` depends only on the local session file; it must not require the server to be online.

### 12.4 Cleanup Policy

Recommended cleanup capabilities:

- `cookey rm --expired`
- Clean up orphaned daemon descriptors on startup.
- Purge old sessions based on `session_retention_days`.

---

## 13. Summary

This version of Cookey's architecture is CLI-first. The goal is not "browser automation capabilities" — it is "reliably deliver a mobile login result to the local terminal and save it in a Playwright-consumable format."

Key decisions:

- CLI generates a long-term `ed25519` identity key on first run.
- Each run generates a device fingerprint and ensures `sessions/` and `daemons/` directories exist.
- `login` only initiates the request and waits in the background; it does not block the foreground terminal.
- The background child receives the session via WebSocket or long polling.
- Sessions are always written to `~/.cookey/sessions/{rid}.json`.
- Session files are Playwright-compatible at the top level; CLI metadata lives in `_cookey`.
- `status`, `export`, `list`, `rm`, `config`, and `server` form the complete CLI surface.

This design preserves the three core goals — minimal, zero-knowledge, self-hostable — while defining CLI local state management clearly enough to implement directly.
