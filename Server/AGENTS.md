# Server

Swift relay server built on Hummingbird (v2.0.0+). Zero-knowledge — only forwards encrypted session blobs.

## Dependencies

- `hummingbird/hummingbird` (>=2.0.0) — HTTP server
- `hummingbird/hummingbird-websocket` (>=2.0.0) — WebSocket transport
- `apple/swift-crypto` (>=3.0.0) — X25519, P256 (APNs JWT signing)

## Source Layout

```
Sources/Server/
├── main.swift           # Entry point, config parsing, cleanup scheduler
├── Models.swift         # Request/session data types
├── Routes.swift         # HTTP + WebSocket route handlers
├── Storage.swift        # Actor-based in-memory request store
└── APNSClient.swift     # Apple Push Notification JWT client
```

## Key Concepts

- **In-memory only**: no database, all state in `RequestStorage` actor with TTL-based expiry
- **Dual transport**: WebSocket preferred, HTTP long-poll fallback — both deliver the same payload
- **One-shot delivery**: session deleted immediately after CLI receives it, or auto-deleted on TTL
- **APNs**: optional push notification support with bearer token caching

## API Endpoints

- `POST /v1/requests` — register pending login request
- `GET /v1/requests/{rid}` — query request status
- `GET /v1/requests/{rid}/ws` — WebSocket session delivery
- `GET /v1/requests/{rid}/wait` — long-poll session delivery
- `POST /v1/requests/{rid}/session` — mobile uploads encrypted session
- `POST/DELETE /v1/devices/{device_id}/apn-token` — APNs registration

## Conventions

- All types marked `Sendable` for Swift Concurrency safety
- Actor isolation for shared mutable state (`RequestStorage`, `APNSClient`)
- Config priority: CLI args > environment vars > defaults
- 30-second background cleanup task for expired requests
- Default TTL: 300 seconds, max payload: 1 MB
