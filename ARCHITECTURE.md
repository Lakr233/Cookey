# HelpMeIn Architecture Design Draft

## Overview

HelpMeIn (帮我登进去) is a **Remote Login Proxy System** that allows CLI-based agents to delegate web authentication to a trusted mobile device.

### Core Use Case

```
[Agent in Container] --(1. Request)--> [Server] --(2. APN Push)--> [iOS Device]
                                               ^                       |
                                               |                       v
[Agent receives session] <--(5. Callback)-- [Server] <--(3. Login) [User]
                                                    <--(4. Cookies)--
```

## System Architecture

### 1. Client (CLI Agent)

**Location**: `/Client/CLI/`

**Responsibilities**:
- Initiate login requests with target URL
- Display QR code / request ID for pairing
- Poll or WebSocket for session data
- Store and manage session tokens

**Key Commands**:
```bash
helpmein login <url>              # Request remote login
helpmein status <request-id>      # Check request status
helpmein devices                  # List paired devices
helpmein pair                   # Initiate device pairing
```

**Tech Stack**:
- Swift (native binary via Swift Package Manager)
- AsyncHTTPClient for networking
- KeychainAccess for secure storage

### 2. Mobile Client (iOS App)

**Location**: `/Frontend/iOS/HelpMeIn/`

**Responsibilities**:
- Receive APN push notifications for login requests
- Display in-app browser for user authentication
- Extract cookies/session after successful login
- Send session data back to server
- Manage device identity and keys

**Key Features**:
- Push notification handling (background + foreground)
- In-app browser (SFSafariViewController or WKWebView)
- Secure enclave for device key storage
- Session preview before sending back

**Tech Stack**:
- SwiftUI for UI
- @Observable pattern for state management
- CryptoKit for key management
- UserNotifications framework for APN

### 3. Server (Backend API)

**Location**: `/Backend/Server/`

**Responsibilities**:
- Device registration and pairing
- Request routing and state management
- APN push notification delivery
- Secure session data relay
- Rate limiting and abuse prevention

**API Endpoints**:
```
POST /v1/devices/register           # Register new device
POST /v1/devices/verify             # Verify device pairing
POST /v1/requests                   # Create login request
GET  /v1/requests/:id               # Poll request status
POST /v1/requests/:id/complete      # Complete with session data
POST /v1/push/apn                 # Internal APN delivery
```

**Tech Stack**:
- Swift + Hummingbird (Vapor alternative, lighter)
- Redis for request state storage
- PostgreSQL for device/user persistence
- APNSwift for Apple Push Notification

**Data Models**:
```swift
// Device
struct Device: Codable {
    let id: UUID
    let publicKey: String
    let apnToken: String
    let name: String
    let createdAt: Date
    let lastSeenAt: Date
}

// Login Request
struct LoginRequest: Codable {
    let id: UUID
    let targetURL: URL
    let requestingDeviceId: UUID
    let status: RequestStatus  // pending | active | completed | expired
    let sessionData: SessionData?
    let createdAt: Date
    let expiresAt: Date
}

// Session Data
struct SessionData: Codable {
    let cookies: [Cookie]
    let localStorage: [String: String]?
    let userAgent: String
}
```

### 4. Website (Landing + Docs)

**Location**: `/Frontend/Web/`

**Responsibilities**:
- Product landing page
- CLI download links
- Documentation
- Privacy policy

**Tech Stack**:
- Static site generator (Hugo or VitePress)
- Hosted on GitHub Pages / Cloudflare Pages

## Security Design

### Device Pairing Flow

```
1. CLI generates keypair (ed25519)
2. CLI displays public key as QR code / text
3. User scans with iOS app
4. iOS generates its own keypair
5. iOS sends: {cli_pubkey, device_pubkey, apn_token, device_name}
6. Server verifies CLI pubkey matches pending pairing
7. Server returns: device_id, server_pubkey
8. Both sides store keys, future requests signed
```

### Request Authentication

- All requests signed with device private key
- Server verifies signature before processing
- Short-lived request IDs (5-10 min expiry)
- Rate limiting per device

### Session Data Protection

- Session data encrypted with CLI's public key
- Server cannot read session content (zero-knowledge relay)
- Auto-expire after delivery or timeout

## Data Flow

### 1. Device Pairing

```mermaid
sequenceDiagram
    participant CLI as CLI Agent
    participant S as Server
    participant iOS as iOS App
    
    CLI->>CLI: Generate keypair
    CLI->>CLI: Display QR (pubkey)
    
    iOS->>iOS: Scan QR, get CLI pubkey
    iOS->>iOS: Generate device keypair
    iOS->>iOS: Request APN token
    
    iOS->>S: POST /devices/register
    S->>S: Store pending pairing
    
    CLI->>S: GET /pairing/status
    S->>CLI: {device_info, server_pubkey}
    
    CLI->>CLI: Verify device signature
    CLI->>CLI: Store device_id + keys
```

### 2. Login Request

```mermaid
sequenceDiagram
    participant CLI as CLI Agent
    participant S as Server
    participant APN as APN Service
    participant iOS as iOS App
    participant Web as Target Website
    
    CLI->>CLI: Create signed request
    CLI->>S: POST /requests {url, device_id, signature}
    S->>S: Verify signature
    S->>S: Create request record
    S->>APN: Push notification
    
    APN->>iOS: "Login request: example.com"
    iOS->>iOS: User taps notification
    iOS->>S: GET /requests/:id (mark active)
    
    iOS->>Web: Open in-app browser
    Web->>iOS: User completes login
    iOS->>iOS: Extract cookies/session
    
    iOS->>S: POST /requests/:id/complete
    Note over iOS,S: Session encrypted with CLI pubkey
    
    S->>APN: Push "completed"
    S->>CLI: (Polling/WebSocket) Session data
    CLI->>CLI: Decrypt and store
```

## Technical Decisions

### Why Hummingbird over Vapor?

- Lighter weight, faster cold start
- Better suited for simple API server
- Swift-native, consistent with client

### Why APN over WebSocket for iOS?

- WebSocket doesn't work reliably in background
- Push notification is the standard way to wake apps
- Better battery life

### Why ed25519?

- Fast signature verification
- Compact keys (good for QR codes)
- Native support in CryptoKit

## Development Phases

### Phase 1: Core Protocol (Week 1-2)

- [ ] Server: Device registration API
- [ ] Server: Request creation/completion API
- [ ] iOS: Basic UI + APN handling
- [ ] iOS: In-app browser integration
- [ ] CLI: Pairing flow
- [ ] CLI: Request + polling

### Phase 2: Security & Polish (Week 3)

- [ ] End-to-end encryption for sessions
- [ ] Signature verification everywhere
- [ ] Rate limiting
- [ ] Error handling & retry logic
- [ ] Request expiration cleanup

### Phase 3: Features (Week 4)

- [ ] Multiple device support
- [ ] Request history
- [ ] Website landing page
- [ ] Documentation
- [ ] CLI distribution (Homebrew, etc.)

## Open Questions

1. **WebSocket vs Polling for CLI?**
   - WebSocket: Real-time but more complex
   - Polling: Simpler, sufficient for MVP

2. **Session Data Format?**
   - Just cookies or full localStorage?
   - Support for custom headers?

3. **Multi-User Support?**
   - Single user per device for MVP?
   - Or multiple CLI agents per iOS device?

4. **Server Hosting?**
   - Self-hosted option?
   - Managed service?

## Next Steps

1. Create backend server scaffold (Hummingbird)
2. Set up APNS certificates / Firebase
3. Implement device pairing flow (simplest first)
4. Test end-to-end with hardcoded values
5. Add crypto layer

---

**Author**: @yukine-chan  
**Status**: Draft - Open for discussion  
**Target**: Merge as `ARCHITECTURE.md` after review
</content>