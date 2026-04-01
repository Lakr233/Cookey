# CLI

Swift Package Manager executable targeting macOS 13+. The `cookey` binary is the user-facing CLI tool.

## Dependencies

- `apple/swift-crypto` (>=3.0.0) — Ed25519, X25519, SHA256/SHA512
- `CryptoBox` (local: `../Packages/CryptoBox`) — XSalsa20-Poly1305 authenticated encryption

## Source Layout

```
Sources/
├── CLI/
│   └── main.swift           # Entry point, command dispatch
└── Core/
    ├── Models.swift         # Data types (LoginManifest, SessionFile, etc.)
    ├── Config.swift         # Bootstrap, paths, config persistence
    ├── KeyManager.swift     # Ed25519/X25519 key operations
    ├── Daemon.swift         # Background process fork/detach
    ├── RelayClient.swift    # HTTP client for relay server
    └── QRCode.swift         # Terminal QR rendering (shells out to qrencode)
```

## Key Concepts

- **Bootstrap**: every entry point runs the same sequence — create `~/.cookey/`, ensure keypair, generate device fingerprint, clean stale daemons
- **Commands**: `login`, `status`, `export`, plus internal `__daemon`
- **Process model**: `login` forks a detached child daemon that waits for the session via WebSocket or long-poll, then writes to `~/.cookey/sessions/{rid}.json`
- **Crypto flow**: Ed25519 identity key stored long-term; converted to X25519 at runtime for ECDH session decryption

## Conventions

- Enum-driven command dispatch with guard-based argument parsing
- `--json` flag for machine-readable output on all commands
- Atomic file writes: write to `.tmp`, fsync, rename
- POSIX permissions enforced (0600 for secrets, 0700 for dirs)
- Exit codes: 0 success, 1 CLI error, 3 expired, 5 daemon error
- Custom `Error` + `LocalizedError` conformance across modules
- `BootstrapContext` encapsulates all initialized state
