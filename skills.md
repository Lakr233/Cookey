# cookey

CLI tool to capture authenticated browser sessions from iPhone as
Playwright-compatible storageState JSON.

## Install

- macOS: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-macOS.zip
- Linux x86_64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-x86_64.zip
- Linux aarch64: https://github.com/Lakr233/Cookey/releases/latest/download/cookey-linux-aarch64.zip
- This file: https://github.com/Lakr233/Cookey/releases/latest/download/skills.md

## Commands

- `cookey request start <url>` — start session capture
- `cookey request refresh <url>` — refresh an existing session using the latest local session for that target
- `cookey request status [rid]` — check request or delivery status
- `cookey session export [rid]` — print Playwright `storageState.json` to stdout
- `cookey session list` — list local requests and sessions
- `cookey session delete <rid>` — remove one local request/session pair
- `cookey session clean` — remove all inactive local requests/sessions
- `cookey config get [key]` / `cookey config set <key> <value>` — inspect or update CLI defaults

Legacy aliases still work for now:

- `cookey login` → `cookey request start`
- `cookey status` → `cookey request status`
- `cookey export` → `cookey session export`

## Usage

1. `cookey request start <target_url>` → pair key / QR appears
2. User scans QR with Cookey iPhone app and logs in
3. `cookey session export <rid> > storageState.json`
4. Pass storageState to Playwright or browser automation
5. `cookey request refresh <target_url>` → refresh an expired session using the existing cookies as a seed
