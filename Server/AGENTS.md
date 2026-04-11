# Server

Go relay server using stdlib `net/http` + `gorilla/websocket`. Zero-knowledge — only forwards encrypted session blobs.

## Dependencies

- `github.com/gorilla/websocket` — WebSocket transport
- Go stdlib `crypto/ecdsa`, `crypto/x509` — P256 (APNs JWT signing)
- Go stdlib `crypto/rsa`, `crypto/x509` — RSA (FCM OAuth2 JWT signing)

## Source Layout

```
.
├── main.go         # Entry point, config parsing, cleanup goroutine, server startup
├── models.go       # Request/session/config data types
├── routes.go       # HTTP route handlers
├── websocket.go    # WebSocket upgrade + session delivery
├── storage.go      # In-memory request store with mutex + waiter channels
├── apns.go         # Apple Push Notification JWT client
├── fcm.go          # Firebase Cloud Messaging HTTP v1 API client
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
- **FCM**: optional Firebase Cloud Messaging support via HTTP v1 API with OAuth2 JWT Bearer flow (RS256), access token caching (50 min)
- **APNTokenBlocker**: rate-limits and temporarily blocks APNs/FCM tokens/IPs after repeated failures (3 failures → 5 min block)

## Push Notification Configuration

Both APNs and FCM are optional and independently configurable via environment variables.

### APNs (iOS)

| Variable | Description |
|---|---|
| `COOKEY_APNS_TEAM_ID` | Apple Developer team ID |
| `COOKEY_APNS_KEY_ID` | APNs authentication key ID |
| `COOKEY_APNS_BUNDLE_ID` | iOS app bundle identifier |
| `COOKEY_APNS_PRIVATE_KEY_PATH` | Path to APNs `.p8` private key file |

All four are required to enable APNs.

### FCM (Android)

| Variable | Description |
|---|---|
| `COOKEY_FCM_SERVICE_ACCOUNT_PATH` | Path to Firebase service account JSON file |
| `COOKEY_FCM_PROJECT_ID` | Firebase project ID (auto-detected from service account file if omitted) |

Only `COOKEY_FCM_SERVICE_ACCOUNT_PATH` is required; `project_id` is read from the JSON file automatically.

### Docker Deployment

In `compose.yaml`, push notification keys are mounted as read-only volumes into the API container:

```yaml
volumes:
  - ./Secret/apns.p8:/keys/apns.p8:ro
  - ./Secret/fcm-service-account.json:/keys/fcm-service-account.json:ro
```

Secret files in `Secret/` must have `0600` permissions and are never committed to the repository.

### Push Flow

Push notifications are triggered when the CLI uploads an encrypted seed session (`POST /v1/requests/{rid}/seed-session`) for refresh flows. The server sends APNs or FCM push based on which token the mobile client registered with the request. Each token is rate-limited to 3 pushes per 5-minute window.

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
