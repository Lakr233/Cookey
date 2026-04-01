# cookey

CLI tool to capture authenticated browser sessions from iPhone as
Playwright-compatible storageState JSON.

## Install
https://github.com/Lakr233/Cookey/releases/latest

## Commands
- `cookey login <url>` — start session capture, shows QR code
- `cookey status [rid]` — check if session arrived
- `cookey export <rid>` — print storageState.json to stdout
- `cookey list` — show all sessions
- `cookey rm <rid>` — delete a session

## Usage
1. `cookey login <target_url>` → QR code appears
2. User scans QR with Cookey iPhone app and logs in
3. `cookey export <rid> > storageState.json`
4. Pass storageState to Playwright or browser automation
