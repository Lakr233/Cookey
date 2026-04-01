# Cookey

Cookey is a minimal, self-hostable, CLI-first tool for scanning a QR code on mobile, logging in to a target website, and delivering the resulting browser session back to the local terminal as Playwright-compatible storageState JSON.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design document.

Three components: CLI (terminal), Mobile App (iOS), Relay Server (in-memory).
Trust model: user trusts CLI + mobile device; relay server is untrusted (zero-knowledge).

## Repository Layout

| Directory                                           | Purpose                          | Details                                                                   |
| --------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------- |
| [CLI/](CLI/AGENTS.md)                               | Swift CLI tool (`cookey`)        | login, status, export commands; background daemon; ed25519/x25519 crypto  |
| [Server/](Server/AGENTS.md)                         | Swift relay server (Hummingbird) | In-memory request storage; WebSocket + long-poll transport; APNs          |
| [Frontend/iOS/](Frontend/iOS/AGENTS.md)             | iOS app (SwiftUI)                | QR scanner, in-app browser, cookie/localStorage capture, encrypted upload |
| [Packages/CryptoBox/](Packages/CryptoBox/AGENTS.md) | Shared Swift crypto library      | XSalsa20-Poly1305 authenticated encryption with Curve25519 key agreement  |
| [Web/](Web/AGENTS.md)                               | Static marketing/docs site       | Landing page, get-started guide, llms.txt; served via nginx/Docker        |
| [Scripts/](Scripts/AGENTS.md)                       | Build and CI scripts             | Universal binary builds, code signing, notarization, CI keychain setup    |

## Cross-Cutting Conventions

- All Swift code uses 4-space indentation, opening braces on same line
- Modern Swift: @Observable, async/await, actors, @MainActor
- JSON uses snake_case field names with CodingKeys mapping
- ISO8601 date encoding throughout
- File permissions: 0600 for secrets, 0700 for directories
- Encryption: ed25519 identity keys, x25519 ECDH, XSalsa20-Poly1305
