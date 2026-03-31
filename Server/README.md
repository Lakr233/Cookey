# Cookey Relay Server

A lightweight, zero-knowledge relay server for Cookey - built with Swift and Hummingbird.

## Features

- **Zero Knowledge**: Server only stores encrypted session data, never sees plaintext
- **In-Memory Storage**: No database required, all data stored in memory with TTL
- **WebSocket & Long Polling**: Dual transport support for real-time updates
- **Ephemeral Key Exchange**: X25519 ECDH for secure session encryption
- **Auto-Cleanup**: Automatic cleanup of expired requests every 30 seconds

## API Endpoints

### POST /v1/requests
Create a new login request (CLI → Server)

```json
{
  "rid": "r_8GQx8tY0j8x3Yw2N",
  "target_url": "https://example.com/login",
  "cli_public_key": "base64-x25519-pubkey",
  "device_fingerprint": "base64url-sha256",
  "expires_at": "2026-03-28T12:06:03Z"
}
```

### GET /v1/requests/{rid}
Get request status

### GET /v1/requests/{rid}/wait?timeout=30
Long polling for session (CLI daemon)

### WebSocket /v1/requests/{rid}/ws
WebSocket connection for real-time updates

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

## Building

```bash
cd /data/projects/Cookey-server
swift build
```

## Running

```bash
# Run with defaults
swift run Server

# Custom port
swift run Server --port 3000

# Full options
swift run Server --host 0.0.0.0 --port 8080 --public-url https://relay.example.com --ttl 300 --max-payload 1048576
```

## Environment Variables

- `COOKEY_HOST` - Bind host
- `COOKEY_PORT` - Bind port
- `COOKEY_PUBLIC_URL` - Public URL for QR codes

## Architecture

Based on Cookey Architecture Document sections 6-8 and 11:

1. **Zero-Knowledge Design**: Server never sees plaintext cookies/session data
2. **Ephemeral Storage**: All data expires after TTL (default 5 minutes)
3. **Dual Transport**: WebSocket preferred, long-polling fallback
4. **One-Shot Delivery**: Session delivered once then immediately purged

## Security

- X25519 ECDH for key exchange
- XSalsa20-Poly1305 for encryption
- Server only handles encrypted blobs
- No persistent storage of session data
- Automatic cleanup prevents data accumulation

## License

MIT License - Part of the Cookey project