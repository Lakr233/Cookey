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
    ├── qrcode/render.go       # Terminal QR rendering (shells out to qrencode)
    └── relay/client.go        # HTTP relay client
```

## Key Concepts

- **Bootstrap**: every entry point runs the same sequence — create `~/.cookey/`, ensure keypair, generate device fingerprint, clean stale daemons
- **Commands**: grouped `request`, `session`, and `config` commands; legacy flat aliases remain for compatibility; internal `__daemon`
- **Process model**: `login` launches a detached child daemon that waits for the session, then writes to `~/.cookey/sessions/{rid}.json`
- **Crypto flow**: Ed25519 identity key stored long-term; converted to X25519 at runtime for ECDH session decryption

## Conventions

- Small internal packages with the CLI surface concentrated in `internal/cli`
- `--json` flag for machine-readable output on all user-facing status/login commands
- Atomic file writes: temp file, `fsync`, rename
- POSIX permissions enforced (0600 for secrets, 0700 for dirs)
- Exit codes: 0 success, 1 CLI error, 3 expired, 5 daemon error
- Swift compatibility is verified with a committed golden fixture in `internal/crypto/testdata/`
