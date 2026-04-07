# Cookey

Cookey is a minimal, self-hostable, CLI-first tool that lets you sign in on your phone and bring the resulting browser session back to your terminal as Playwright-compatible `storageState` JSON.

## What It Does

- Start a login request from the CLI
- Scan the QR code on iPhone
- Complete login in the in-app browser
- Return the encrypted session to the CLI
- Reuse it in Playwright or other automation flows

## How It Works

1. The CLI creates a short-lived login request
2. The mobile app opens the target site and logs in
3. Session data is encrypted on-device
4. The relay server transports only encrypted blobs
5. The CLI decrypts and exports `storageState` JSON locally

## Components

- `CommandLineTool/` — Go CLI and local daemon
- `Frontend/Apple/` — SwiftUI iPhone app for QR scan and login
- `Server/` — Go relay server with in-memory storage
- `Web/` — static site and docs

## Security Model

- End-to-end encrypted session handoff
- Relay server is treated as untrusted
- No plaintext cookies or session data on the server
- Short-lived, in-memory request/session storage

## Use Cases

- Log in once on mobile, then automate locally
- Import authenticated state into Playwright tests
- Access mobile-only or MFA-heavy login flows from the CLI

## Agent Skills

Install the Cookey CLI skill for Claude Code and other AI agents via [Vercel Skills CLI](https://github.com/vercel-labs/skills):

```sh
npx skills add Lakr233/Cookey --skill website-login
```

## Status

Cookey is organized as a multi-component repo covering the CLI, relay server, Apple app, and website.
