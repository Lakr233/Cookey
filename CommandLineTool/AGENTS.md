# CommandLineTool

Go executable module targeting macOS 13+ and Linux. The `cookey` binary is the user-facing CLI tool.

## Dependencies

- `golang.org/x/crypto` — Ed25519, X25519, NaCl box primitives

## Source Layout

```
.
├── main.go                    # Thin entry point
└── internal/
    ├── cli/                   # CLI parsing, grouped command dispatch, rendering
    ├── config/store.go        # Bootstrap, paths, config persistence, status resolution
    ├── crypto/keys.go         # Ed25519/X25519 key operations and envelope decryption
    ├── crypto/keys_test.go    # Go round-trip tests plus Swift golden fixture compatibility
    ├── daemon/daemon.go       # Detached child launch and inline daemon execution
    ├── daemon/daemon_test.go  # Daemon process management tests
    ├── models/models.go       # Data types (LoginManifest, SessionFile, etc.)
    ├── qrcode/render.go       # Terminal QR rendering and Cookey/jump link helpers
    └── relay/client.go        # HTTP relay client
```

## Key Concepts

- **Bootstrap**: every entry point runs the same sequence — create `~/.cookey/`, ensure keypair, generate device fingerprint, clean stale daemons
- **Commands**: grouped `request`, `session`, and `config` commands; internal `__daemon`
- **Process model**: `request start` / `request refresh` launch a detached child daemon that waits for the session, then writes to `~/.cookey/sessions/{rid}.json`
- **Crypto flow**: Ed25519 identity key stored long-term; converted to X25519 at runtime for ECDH session decryption

## CLI Behavior

### Command Surface

- `cookey request start <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]`
- `cookey request refresh <target_url> [--server URL] [--timeout SECONDS] [--qr] [--json] [--attach]`
- `cookey request status [rid] [--latest] [--watch] [--json]`
- `cookey session export [rid] [--latest] [--out FILE] [--pretty]`
- `cookey session list [--json]`
- `cookey session delete <rid> [--json]`
- `cookey session clean [--json]`
- `cookey config get [key] [--json]`
- `cookey config set <key> <value> [--json]`

### Request Lifecycle

- `request start` creates a fresh request ID, registers it with the relay, prints the pair key / deep link, and starts a waiter process.
- `request refresh` requires an existing local session for the same target URL. It seeds the request with the latest local cookies and origin storage for that target, then merges newly received state over the stored session.
- If a prior session contains device info, refresh also carries APNs metadata so the mobile app can be nudged directly. If device info is missing, refresh still works, but the user must complete the flow from QR / pair key.
- `request status` prefers local state from `~/.cookey/daemons/` and `~/.cookey/sessions/`. If the requested RID is not found locally, it falls back to relay status using the configured default server.
- `request status --watch` polls once per second and exits when the request reaches `ready`, `expired`, `error`, `orphaned`, or `missing`.

### Status Semantics

- `waiting`: daemon is alive and waiting on the relay WebSocket.
- `receiving`: encrypted session arrived and is being decrypted / written locally.
- `ready`: local session file exists and can be exported.
- `expired`: request timed out before a usable session was written.
- `orphaned`: descriptor says the request was active, but the recorded daemon PID is no longer alive.
- `error`: daemon failed because of relay, decrypt, parse, or local write errors.
- `missing`: no local record exists; remote fallback also did not find the RID.

### Session Commands

- `session export` emits Playwright-compatible JSON with only `cookies` and `origins`. It does not expose Cookey's internal `_cookey` metadata block.
- `session export --latest` resolves the most recently updated local session file.
- If `session export` cannot find a session file but can find a daemon descriptor, it reports the descriptor status in the error message so callers can distinguish `expired` from other failures.
- `session list` returns the union of local daemon descriptors and local session files, newest first.
- `session delete` and `session clean` never kill active daemon processes. They refuse or skip requests that are still `waiting` or `receiving` with a live PID.

### Config Keys

- `default-server`: default relay base URL. Must parse as a valid relay URL and use `https`.
- `timeout-seconds`: default request timeout for `request start` and `request refresh`.
- `session-retention-days`: stored in config, but not currently enforced by automatic cleanup logic.

## Daemon Process Model

- Default behavior is detached. `request start` / `request refresh` call `daemon.LaunchDetached`, which re-executes the current binary as `cookey __daemon <payload>`.
- Detached daemons start in a new session with `setsid`, and stdin/stdout/stderr are redirected to `/dev/null`.
- The parent CLI process waits only until the daemon descriptor file is written, then returns success to the caller.
- `--attach` skips detached launch and runs the same wait/decrypt/write flow inline via `daemon.RunInline`.
- Inline mode means the current process must stay alive until delivery completes. This is only safe when the caller intentionally keeps the process attached.
- Unless your tool call harness supports automatic process detach (e.g., `nohup` or an init system), DO NOT use `--attach`. Without detach, the verification code will expire when the parent process exits.
- `--no-detach` still exists as a deprecated compatibility flag and is treated as `--attach`.

## Exit Codes

- `0`: success.
- `1`: user-facing CLI error from argument validation, command parsing, bootstrap, or other top-level failures returned through `main.go`.
- `3`: inline daemon expired while waiting for session delivery. This is only surfaced to the original caller when using `--attach`.
- `5`: inline daemon failed because of relay, decrypt, parse, or local filesystem errors. This is only surfaced to the original caller when using `--attach`.

In detached mode, the initial `request start` / `request refresh` command still exits `0` after launching the daemon successfully. The detached daemon's terminal state is recorded in `~/.cookey/daemons/{rid}.json` and surfaced through `cookey request status`.

## Conventions

- Small internal packages with the CLI surface concentrated in `internal/cli`
- Atomic file writes: temp file, `fsync`, rename
- POSIX permissions enforced (0600 for secrets, 0700 for dirs)
- Exit codes: 0 success, 1 CLI error, 3 expired, 5 daemon error
- Swift compatibility is verified with a committed golden fixture in `internal/crypto/testdata/`
