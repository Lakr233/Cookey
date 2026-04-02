# Cookey

Cookey is a minimal, self-hostable, CLI-first tool for scanning a QR code on mobile, logging in to a target website, and delivering the resulting browser session back to the local terminal as Playwright-compatible storageState JSON.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design document.

Three components: CLI (terminal), Mobile App (iOS), Relay Server (in-memory).
Trust model: user trusts CLI + mobile device; relay server is untrusted (zero-knowledge).

## Repository Layout

| Directory                                                                         | Purpose                     | Details                                                                   |
| --------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------- |
| [CommandLineTool/](CommandLineTool/AGENTS.md)                                     | Go CLI tool (`cookey`)      | login, status, export commands; background daemon; ed25519/x25519 crypto  |
| [Server/](Server/AGENTS.md)                                                       | Go relay server             | In-memory request storage; WebSocket transport; APNs                      |
| [Frontend/Apple/](Frontend/Apple/AGENTS.md)                                       | Apple app (SwiftUI)         | QR scanner, in-app browser, cookie/localStorage capture, encrypted upload |
| [Frontend/Apple/Packages/CryptoBox/](Frontend/Apple/Packages/CryptoBox/AGENTS.md) | Shared Swift crypto library | XSalsa20-Poly1305 authenticated encryption with Curve25519 key agreement  |
| [Web/](Web/AGENTS.md)                                                             | Static marketing/docs site  | Landing page, get-started guide, llms.txt; served via nginx/Docker        |
| [Scripts/](Scripts/AGENTS.md)                                                     | Build and CI scripts        | Universal binary builds, code signing, notarization, CI keychain setup    |

## Cross-Cutting Conventions

- All Swift code uses 4-space indentation, opening braces on same line
- Modern Swift: @Observable, async/await, actors, @MainActor
- JSON uses snake_case field names with CodingKeys mapping
- ISO8601 date encoding throughout
- File permissions: 0600 for secrets, 0700 for directories
- Encryption: ed25519 identity keys, x25519 ECDH, XSalsa20-Poly1305

## Deployment Conventions

- Production deploys sync only compose.yaml, Server/, and Web/
- When using rsync for deploys, use `--delete` only on the specific target directory being synced (for example `Server/` or `Web/`), never on the repo root or parent deploy path
- Remote environment files and secret files are maintained on the server and must not be overwritten by rsync
- Build and restart production with docker compose on the remote host after syncing those paths
- Production deploy target is provided out-of-band by the user/session and has remote-managed Cloudflare tunnel configuration that must be preserved exactly unless the user explicitly asks to change it
- Do not print, commit, or add the production server username, hostname, or address to repository files, logs intended for handoff, or user-facing summaries unless the user explicitly asks for it
- Required production tunnel routes are api.cookey.sh -> http://api:5800 and cookey.sh -> http://web:3000
- Cloudflared tunnel tokens for those routes are remote secrets; never commit them, print them unnecessarily, or overwrite them during deploys
- Before any production deploy that touches compose or tunnel services, inspect and preserve the remote tunnel-related environment/configuration instead of replacing it from local files
