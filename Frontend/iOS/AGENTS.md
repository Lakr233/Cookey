# Frontend/iOS

SwiftUI iOS app for Cookey. Scans QR codes, opens target sites in an in-app browser, captures cookies and localStorage, encrypts the session, and uploads it to the relay server.

## Dependencies

- `CryptoBox` (local: `../../Packages/CryptoBox`) — XSalsa20-Poly1305 encryption

## Source Layout

```
Cookey/
├── Backend/
│   ├── APIClient.swift              # URLSession HTTP client (health, upload, APNs)
│   ├── Models.swift                 # EncryptedSessionEnvelope, CapturedCookie/Origin/Session
│   ├── SessionUploadModel.swift     # Main @Observable state machine
│   ├── PushRegistrationCoordinator.swift  # APNs device token handling
│   ├── DeepLink.swift               # cookey:// URL scheme parsing
│   └── AppEnvironment.swift         # API endpoint config
├── Interface/
│   ├── ContentView.swift            # Root view, UI orchestration
│   ├── ScannerView.swift            # AVCaptureSession QR scanner (UIViewRepresentable)
│   ├── InAppBrowserView.swift       # WKWebView cookie/localStorage capture
│   ├── APNConsentView.swift         # Push notification permission prompt
│   └── UploadProgressView.swift     # Upload status display
├── CookeyAppDelegate.swift          # UIApplicationDelegate (push notifications)
├── main.swift                       # App entry point
└── Resources/
```

## Key Concepts

- **State machine**: `SessionUploadModel` drives the app flow: idle → scanning → browsing → uploading → done/failed
- **Deep link**: `cookey://login?rid=...&server=...&target=...&pubkey=...&device_id=...`
- **Capture**: WKWebView JavaScript evaluation extracts cookies and localStorage after user logs in
- **Encryption**: captured session encrypted with CLI's X25519 public key via CryptoBox before upload

## Build Configuration

- **Targets**: iOS 26.2+, macOS 26.2+ (Catalyst), visionOS
- **Bundle ID**: `wiki.qaq.cookey.app`
- **Entitlements**: App Sandbox, Hardened Runtime, camera access
- **API**: `https://api.cookey.sh` (override with `COOKEY_API_URL` env var)

## Swift Conventions

- 4-space indentation, opening braces on same line
- @Observable macro (not ObservableObject/@Published)
- async/await, @MainActor for UI state
- Early returns, guard statements
- PascalCase types, camelCase properties/methods
- Small focused files, `+Extension.swift` for extensions
- Dependency injection over singletons
- Value types over reference types
