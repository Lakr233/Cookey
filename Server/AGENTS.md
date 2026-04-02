# Server

Go relay server using stdlib `net/http` + `gorilla/websocket`. Zero-knowledge — only forwards encrypted session blobs.

## Dependencies

- `github.com/gorilla/websocket` — WebSocket transport
- Go stdlib `crypto/ecdsa`, `crypto/x509` — P256 (APNs JWT signing)

## Source Layout

```
.
├── main.go         # Entry point, config parsing, cleanup goroutine, server startup
├── models.go       # Request/session/config data types
├── routes.go       # HTTP route handlers
├── websocket.go    # WebSocket upgrade + session delivery
├── storage.go      # In-memory request store with mutex + waiter channels
├── apns.go         # Apple Push Notification JWT client
├── go.mod          # Module definition
├── go.sum          # Dependency checksums
├── Dockerfile      # Multi-stage Docker build (golang:1.24-alpine → alpine:3.21)
└── server_test.go  # Integration tests for HTTP handlers and WebSocket delivery
```

## Key Concepts

- **In-memory only**: no database, all state in `Storage` struct with `sync.RWMutex` and TTL-based expiry
- **WebSocket delivery**: session delivered via WebSocket with text ping/pong keepalive
- **One-shot delivery**: session deleted immediately after CLI receives it, or auto-deleted on TTL
- **APNs**: optional push notification support with JWT bearer token caching (50 min), sandbox/production routing
- **APNTokenBlocker**: rate-limits and temporarily blocks APNs tokens/IPs after repeated failures (3 failures → 5 min block)

## API Endpoints

- `POST /v1/requests` — register pending login request
- `GET /v1/requests/{rid}` — query request status
- `GET /v1/requests/{rid}/ws` — WebSocket session delivery
- `POST /v1/requests/{rid}/session` — mobile uploads encrypted session
- `POST /v1/requests/{rid}/seed-session` — CLI uploads encrypted seed session for refresh flows
- `GET /v1/requests/{rid}/seed-session` — mobile retrieves and clears seed session

## Conventions

- Single `package main`, no sub-packages
- `sync.RWMutex` for shared mutable state, `chan` for WebSocket waiters
- Config priority: environment vars > CLI args > defaults
- 30-second background cleanup goroutine for expired requests
- Default TTL: 300 seconds, max payload: 1 MB
- `Server: Cookey-Relay/1.0` header on all responses
- JSON struct fields ordered alphabetically by tag to match Swift's sortedKeys output
  Swift's sortedKeys output
