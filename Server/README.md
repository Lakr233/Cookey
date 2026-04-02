# Cookey Relay Server

A lightweight relay server for Cookey — built with Go.

## Features

- **End-to-End Encrypted Sessions**: Server only stores encrypted session data, never sees plaintext
- **In-Memory Storage**: No database required, all data stored in memory with TTL
- **WebSocket Transport**: Real-time session delivery via WebSocket
- **Ephemeral Key Exchange**: X25519 ECDH for secure session encryption
- **Auto-Cleanup**: Automatic cleanup of expired requests every 30 seconds
- **Pair Key Resolution**: Optional manual pairing flow resolves a short pair key to the full request metadata
- **Stateless Refresh Push**: APNs refresh push uses token data attached to each refresh request; the server does not store device registrations

## API Endpoints

### POST /v1/requests

Create a new login request (CLI → Server)

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "request_type": "login",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

### GET /v1/requests/{rid}

Get request status

### WebSocket /v1/requests/{rid}/ws

WebSocket connection for real-time session delivery

### POST /v1/requests/{rid}/session

Upload encrypted session (Mobile → Server)

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

### POST /v1/requests/{rid}/seed-session

Upload encrypted seed session (CLI → Server, for refresh flow). The CLI encrypts the existing session and uploads it so the mobile app can pre-load cookies before refreshing. If the refresh request includes `apn_token` and `apn_environment`, the server uses those request-scoped values to send the refresh push.

### GET /v1/requests/{rid}/seed-session

Download encrypted seed session (Server → Mobile, one-shot delivery). The server returns the encrypted seed session blob and immediately purges it from memory.

## Building

```bash
cd Server
go build -o server .
```

## Running

```bash
# Run with defaults
./server

# Custom port
./server --port 3000

# Full options
./server --host 0.0.0.0 --port 8080 --public-url https://relay.example.com --ttl 300 --max-payload 1048576
```

## Docker

```bash
docker compose build api
docker compose up api
```

## Environment Variables

- `COOKEY_HOST` - Bind host
- `COOKEY_PORT` - Bind port
- `COOKEY_PUBLIC_URL` - Public URL for QR codes
- `COOKEY_APNS_TEAM_ID` - Apple Developer team ID
- `COOKEY_APNS_KEY_ID` - APNs key ID
- `COOKEY_APNS_BUNDLE_ID` - App bundle identifier
- `COOKEY_APNS_PRIVATE_KEY_PATH` - Path to APNs .p8 key
- `COOKEY_APNS_SANDBOX` - Use APNs sandbox environment (set to `true` for development)

## Architecture

1. **Encrypted Session Relay**: Server never sees plaintext cookies/session data
2. **Ephemeral Storage**: All data expires after TTL (default 5 minutes)
3. **WebSocket Delivery**: Real-time session delivery with text ping/pong keepalive
4. **One-Shot Delivery**: Session delivered once then immediately purged
5. **Pair Key Metadata**: Manual pair-key entry requires the relay to temporarily store request metadata needed to resolve the short code
6. **Stateless APNs**: APNs tokens are never registered or stored server-side; only refresh requests can trigger push, using token fields embedded in the request

## Trust Model Notes

- **QR / deep-link flow**: the app receives the authenticated request metadata directly from the CLI-generated link.
- **Manual pair-key flow**: the relay temporarily stores request metadata in memory so the app can resolve the short pair key. This includes the CLI public key and request authentication material used for pair-key resolution.
- **What the relay still cannot do**: decrypt uploaded browser sessions. The X25519 private key stays on the CLI, so stored ciphertext remains unreadable to the relay.
- **What changes**: manual pair-key entry is not equivalent to the pure QR / deep-link flow. Because the relay reconstructs the request metadata for the app, this mode requires trusting the relay not to tamper with the resolved metadata.

## Security

- X25519 ECDH for key exchange
- XSalsa20-Poly1305 for encryption
- Server only handles encrypted blobs
- No persistent storage of session data
- Pair-key resolution stores additional request metadata in memory for the lifetime of the request
- Automatic cleanup prevents data accumulation
- APNs token blocking: request-scoped tokens that repeatedly fail delivery are blocked to prevent abuse
- Rate limiting: per-IP and per-device rate limits protect against request flooding

## License

MIT License - Part of the Cookey project
