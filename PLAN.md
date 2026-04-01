# Cookey — Implementation Plan

## Context

The landing page promises a complete flow:

1. Start login on the terminal
2. Scan or open the login request on the phone
3. Transfer the browser session back to the terminal and export it

That flow is not shippable today because the CLI export command is missing, the iOS app stops at a placeholder scanner sheet, the deep-link fallback path is not registered, and the app/server split for encrypted upload is only half wired.

This plan fixes the end-to-end flow first, then adds opt-in APNs so the phone can receive future login requests without the user scanning a QR code every time.

## Principles

- Ship the core session-transfer flow before layering APNs on top.
- Keep platform-specific behavior explicit: scanner and remote notifications are iOS-only; macOS and other platforms use deep links.
- Share crypto through one real cross-platform module instead of copying security-sensitive code.
- Fix environment selection at the configuration boundary, not by threading unused models through the view tree.

## Issues Being Fixed

| Priority | Issue | Fix |
|----------|------|-----|
| High | `cookey export` crashes with "Unknown command" | Add `export` command that emits Playwright `storageState.json` from the saved session file |
| High | iOS "Scan QR Code" opens a placeholder | Replace placeholder with scanner/browser/upload flow |
| High | Deep-link fallback path is broken | Register `cookey://` URL scheme and handle it at app entry |
| High | Current crypto sharing plan is not buildable | Extract XSalsa20/Poly1305 into a real local Swift package shared by CLI and iOS |
| Medium | Browser origin capture is wrong | Capture full origin (`scheme://host[:port]`), not just host |
| Medium | Health check environment fix is wired to an unused model | Move environment selection into `AppEnvironment.current` and let models default from there |
| Medium | Previous APN plan had no callback path and no durable registration semantics | Add iOS app delegate + coordinator, store registrations durably, and send pushes from request creation |

## Execution Order

1. CLI export
2. Shared crypto package
3. iOS deep-link + scanner + browser + encrypted upload
4. Environment cleanup
5. APNs registration and delivery
6. Verification across CLI, simulator, physical device, and local relay

---

## 1. CLI — `cookey export`

### `CLI/Sources/CLI/main.swift`

Add a new command:

```swift
case "export":
    try handleExport(arguments: args)
```

Add a private helper type near the other output structs:

```swift
private struct PlaywrightStorageState: Encodable {
    let cookies: [BrowserCookie]
    let origins: [OriginState]
}
```

Implement:

```text
cookey export [rid] [--out FILE] [--pretty]
```

Behavior:

- `rid` is optional
- If omitted, use `ConfigStore.latestSessionRID(in: context.paths)`
- Read `SessionFile` from `context.paths.sessionURL(for: rid)`
- Emit only `cookies` and `origins`
- `--pretty` enables `.prettyPrinted` and `.sortedKeys`
- `--out FILE` writes to disk; otherwise print to stdout

Update `parseFlags`:

- value-taking flags: add `out`
- boolean flags: add `pretty`

Update `printUsage` to include:

```text
cookey export [rid] [--out FILE] [--pretty]
```

No other CLI behavior changes are required for this step.

---

## 2. CLI + Server — Stable Device Identifier

APNs should target the CLI machine that initiated the login request, so the request manifest needs a stable machine identifier.

### `CLI/Sources/Core/Config.swift`

Keep this under the existing Cookey root instead of inventing a second config tree:

```swift
public let deviceIdentifier: URL

// in AppPaths.init
self.deviceIdentifier = root.appendingPathComponent("device_id")
```

Add:

```swift
public static func loadOrCreateDeviceIdentifier(at url: URL) throws -> String
```

Rules:

- Trim trailing whitespace/newlines when reading
- Generate `UUID().uuidString.lowercased()` when absent
- Store with file mode `0o600`

Add `deviceIdentifier: String` to `BootstrapContext`.

### `CLI/Sources/Core/Models.swift`

Extend all request-path models, not just the QR deep link:

- `LoginManifest.deviceID` with coding key `device_id`
- `RelayRegisterRequest.deviceID` with coding key `device_id`

### `Server/Sources/Server/Models.swift`

Mirror the same field on the relay side:

- `LoginRequest.deviceID`
- `StoredRequest.deviceID`

### `CLI/Sources/Core/QRCode.swift`

Add:

```swift
URLQueryItem(name: "device_id", value: manifest.deviceID)
```

### `CLI/Sources/Core/RelayClient.swift`

Ensure `register(manifest:)` includes `device_id` in the JSON body it sends to the relay.

This keeps the server request record and the deep link in sync.

---

## 3. Shared Crypto — Real Cross-Platform Package

The previous plan proposed a dependency-free package inside the macOS-only CLI package. That does not work for iOS because the encryption path needs `Curve25519`, and the current CLI package is declared as macOS-only.

### New local package

Create a repo-local Swift package:

`Packages/CryptoBox/Package.swift`

Package shape:

```swift
// swift-tools-version: 5.9
let package = Package(
    name: "CryptoBox",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "CryptoBox", targets: ["CryptoBox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CryptoBox",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        )
    ]
)
```

### `Packages/CryptoBox/Sources/CryptoBox/XSalsa20Poly1305Box.swift`

Move the pure-Swift XSalsa20/Poly1305 implementation here and make it public.

Public API:

```swift
public enum CryptoBoxError: Error {
    case invalidNonce
    case invalidCiphertext
    case authenticationFailed
    case invalidRecipientPublicKey
    case invalidEphemeralPublicKey
    case randomGenerationFailed
}

public enum XSalsa20Poly1305Box {
    public static func open(ciphertext: Data, nonce: Data, sharedSecret: Data) throws -> Data

    public static func seal(
        plaintext: Data,
        recipientPublicKey: Data
    ) throws -> (
        ephemeralPublicKey: Data,
        nonce: Data,
        ciphertext: Data
    )
}
```

`seal` algorithm:

1. Generate a 24-byte nonce with `SecRandomCopyBytes`
2. Create `Curve25519.KeyAgreement.PrivateKey()` for the ephemeral keypair
3. Parse the recipient X25519 public key
4. Derive the shared secret
5. Derive the XSalsa20 subkey exactly symmetrically with `open`
6. Encrypt the plaintext with Salsa20, skipping the first 32 bytes for the Poly1305 key
7. Authenticate the encrypted body with Poly1305
8. Return `(ephemeralPublicKey, nonce, tag + encryptedBody)`

### `CLI/Package.swift`

Add the local package dependency:

```swift
.package(path: "../Packages/CryptoBox")
```

Make `Core` depend on the product:

```swift
.product(name: "CryptoBox", package: "CryptoBox")
```

### `CLI/Sources/Core/KeyManager.swift`

Remove the private in-file `XSalsa20Poly1305Box` implementation.

Import the shared package and map `CryptoBoxError` back into `KeyManagerError` where needed so CLI-facing errors stay stable.

The important design point is that `KeyManagerError` remains a Core concern; the shared crypto package should not depend on Core types.

### iOS app target

Add the same local package (`Packages/CryptoBox`) to `Frontend/iOS/Cookey.xcodeproj`.

This gives both the CLI and iOS target one implementation of the cryptographic primitive.

---

## 4. iOS App — Deep Link, Scanner, Browser, Encrypted Upload

### 4.1 App configuration

#### `Frontend/iOS/Cookey.xcodeproj/project.pbxproj`

Do not use `INFOPLIST_ADDITIONAL_FILE`; instead switch to a checked-in Info.plist because URL-type registration is part of the app contract, not an ad hoc overlay.

Project changes:

- set `GENERATE_INFOPLIST_FILE = NO`
- set `INFOPLIST_FILE = Cookey/Resources/Info.plist`

#### `Frontend/iOS/Cookey/Resources/Info.plist`

Create a real Info.plist containing the current app metadata plus:

- `CFBundleURLTypes` with the `cookey` scheme
- `NSCameraUsageDescription = "Cookey needs camera access to scan QR codes from your terminal."`

Do not flip `ENABLE_RESOURCE_ACCESS_CAMERA` globally. The scanner is iOS-only; macOS should continue using the deep-link path without acquiring new sandbox capabilities it does not need.

### 4.2 Deep link parsing

#### `Frontend/iOS/Cookey/Backend/DeepLink.swift`

```swift
struct DeepLink: Equatable {
    let rid: String
    let serverURL: URL
    let targetURL: URL
    let recipientPublicKeyBase64: String
    let deviceID: String

    init?(url: URL)
}
```

Validation rules:

- scheme must be `cookey`
- host must be `login`
- required query items: `rid`, `server`, `target`, `pubkey`, `device_id`
- `server` and `target` are percent-decoded before URL construction

### 4.3 Upload wire models

#### `Frontend/iOS/Cookey/Backend/Models.swift`

Define iOS-side relay types:

```swift
struct EncryptedSessionEnvelope: Encodable {
    let version: Int
    let algorithm: String
    let ephemeralPublicKey: String
    let nonce: String
    let ciphertext: String
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case version, algorithm, nonce, ciphertext
        case ephemeralPublicKey = "ephemeral_public_key"
        case capturedAt = "captured_at"
    }
}

struct CapturedCookie: Encodable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Double
    let httpOnly: Bool
    let secure: Bool
    let sameSite: String
}

struct CapturedStorageItem: Encodable {
    let name: String
    let value: String
}

struct CapturedOrigin: Encodable {
    let origin: String
    let localStorage: [CapturedStorageItem]
}

struct CapturedSession: Encodable {
    let cookies: [CapturedCookie]
    let origins: [CapturedOrigin]
}
```

Use dedicated types instead of `[[String: String]]` so the encoded shape is explicit and matches the CLI session schema.

### 4.4 Session flow model

#### `Frontend/iOS/Cookey/Backend/SessionUploadModel.swift`

Use one state machine for scan/open/browse/upload:

```swift
@MainActor
@Observable
final class SessionUploadModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case browsing(DeepLink)
        case uploading
        case done
        case failed(String)
        case apnOptIn(DeepLink)
    }

    var phase: Phase = .idle

    init(pushCoordinator: PushRegistrationCoordinator?)

    func startScan()
    func handleURL(_ url: URL)
    func captureAndUpload(
        cookies: [CapturedCookie],
        origins: [CapturedOrigin],
        deepLink: DeepLink
    ) async
    func acceptNotificationOptIn(for deepLink: DeepLink) async
    func dismissSheet()
}
```

Rules:

- `handleURL(_:)` is used by both scanner and app-entry deep links
- `captureAndUpload` builds `CapturedSession`, JSON-encodes it, encrypts it with `XSalsa20Poly1305Box.seal`, and POSTs it to the relay
- after successful upload:
  - if APNs are unavailable on this platform, set `.done`
  - if the app has already answered the opt-in prompt for `serverURL.absoluteString`, set `.done`
  - otherwise set `.apnOptIn(deepLink)`

### 4.5 Scanner

#### `Frontend/iOS/Cookey/Interface/ScannerView.swift`

```swift
#if os(iOS)
import AVFoundation
import SwiftUI

struct ScannerView: UIViewRepresentable {
    let onScanned: (URL) -> Void
}
#endif
```

Implementation requirements:

- run capture-session setup on a background queue
- restrict metadata types to `.qr`
- only accept valid `cookey://` URLs
- stop the session after the first valid scan
- request permission and show a clear denial state if camera access is unavailable

This view is iOS-only. Other platforms do not compile it and do not need camera entitlements.

### 4.6 In-app browser + isolated capture

#### `Frontend/iOS/Cookey/Interface/InAppBrowserView.swift`

Use `WKWebsiteDataStore.nonPersistent()` so the capture is isolated to the current login session.

View shape:

```swift
struct InAppBrowserView: View {
    let deepLink: DeepLink
    let onCaptured: ([CapturedCookie], [CapturedOrigin]) async -> Void
}
```

Browser rules:

- load `deepLink.targetURL`
- toolbar buttons: `Cancel`, `Transfer Session`
- cookie extraction must come from the same non-persistent data store backing the `WKWebView`
- localStorage extraction uses JavaScript on the current page

Origin construction:

- build `scheme://host[:port]` from `URLComponents`
- include the port only when present and non-default
- do not use `webView.url?.host`

### 4.7 API client changes

#### `Frontend/iOS/Cookey/Backend/APIClient.swift`

Add:

```swift
func uploadSession(rid: String, envelope: EncryptedSessionEnvelope) async throws

func registerAPNToken(
    deviceID: String,
    token: String,
    environment: String
) async throws

func unregisterAPNToken(deviceID: String) async throws
```

`uploadSession` posts to:

```text
POST /v1/requests/:rid/session
```

`registerAPNToken` posts to:

```text
POST /v1/devices/:device_id/apn-token
```

`unregisterAPNToken` deletes:

```text
DELETE /v1/devices/:device_id/apn-token
```

### 4.8 App entry and view wiring

#### `Frontend/iOS/Cookey/main.swift`

Keep app-entry routing at the scene boundary, not buried in a child view.

Structure:

```swift
struct Cookey: App {
    @State private var pushCoordinator = PushRegistrationCoordinator()
    @State private var sessionModel: SessionUploadModel

    init() {
        let coordinator = PushRegistrationCoordinator()
        _pushCoordinator = State(initialValue: coordinator)
        _sessionModel = State(initialValue: SessionUploadModel(pushCoordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: sessionModel)
                .onOpenURL { sessionModel.handleURL($0) }
                .task { await pushCoordinator.attach(to: sessionModel) }
        }
    }
}
```

On iOS, this file also hosts the app delegate adaptor described in the APNs section below.

#### `Frontend/iOS/Cookey/Interface/ContentView.swift`

Replace the placeholder sheet with a phase-driven presentation:

- `.scanning` -> `ScannerView` on iOS; fallback instructions elsewhere
- `.browsing(deepLink)` -> `InAppBrowserView`
- `.uploading`, `.done`, `.failed` -> `UploadProgressView`
- `.apnOptIn(deepLink)` -> `APNConsentView`

The landing layout can stay visually unchanged.

#### `Frontend/iOS/Cookey/Interface/UploadProgressView.swift`

Add a simple status view for:

- uploading
- success
- failure

---

## 5. Environment Fix

The previous plan solved the wrong problem by forcing `HealthCheckModel` into the app environment even though nothing reads it.

### `Frontend/iOS/Cookey/Backend/AppEnvironment.swift`

Add:

```swift
enum AppEnvironment {
    static let productionAPIBaseURL = URL(string: "https://api.cookey.sh")!

    static var current: URL {
        if let override = ProcessInfo.processInfo.environment["COOKEY_API_URL"],
           let url = URL(string: override) {
            return url
        }
        return productionAPIBaseURL
    }
}
```

### `Frontend/iOS/Cookey/Backend/HealthCheckModel.swift`

Change the default client source from `productionAPIBaseURL` to `current`:

```swift
private let client: APIClient

init(client: APIClient = APIClient(baseURL: AppEnvironment.current)) {
    self.client = client
}
```

No `main.swift` environment injection is needed unless a real UI starts consuming the model.

---

## 6. APNs — Opt-In Notification Registration and Delivery

APNs is a second phase on top of the working scan/open/upload flow. The key missing pieces are:

- the iOS callback path for device-token registration
- durable token storage on the server
- push delivery triggered directly by request creation
- a notification payload that can reopen the exact login request

### 6.1 iOS push registration coordinator

#### `Frontend/iOS/Cookey/Backend/PushRegistrationCoordinator.swift`

Create a single iOS-only coordinator responsible for remote-notification state:

```swift
@MainActor
@Observable
final class PushRegistrationCoordinator {
    enum State: Equatable {
        case idle
        case requestingPermission
        case waitingForToken(serverURL: URL, deviceID: String)
        case uploadingToken
        case failed(String)
    }

    var state: State = .idle

    func beginRegistration(serverURL: URL, deviceID: String) async
    func handleRegisteredDeviceToken(_ token: Data) async
    func handleRegistrationFailure(_ error: Error)
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any])
    func attach(to model: SessionUploadModel) async
}
```

Responsibilities:

- request notification authorization
- call `UIApplication.shared.registerForRemoteNotifications()`
- remember the in-flight `(serverURL, deviceID)` while waiting for the token callback
- convert the APNs token to lowercase hex
- upload the token to the relay via `APIClient(baseURL: serverURL).registerAPNToken(...)`
- parse push payloads back into a `cookey://login?...` URL or `DeepLink` and hand them to `SessionUploadModel`

This keeps APNs lifecycle code out of `SessionUploadModel`.

### 6.2 iOS app delegate bridge

#### `Frontend/iOS/Cookey/CookeyAppDelegate.swift`

Add an iOS-only app delegate:

```swift
#if os(iOS)
final class CookeyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let pushCoordinator: PushRegistrationCoordinator
}
#endif
```

Responsibilities:

- set `UNUserNotificationCenter.current().delegate = self`
- forward `didRegisterForRemoteNotificationsWithDeviceToken`
- forward `didFailToRegisterForRemoteNotificationsWithError`
- handle notification taps in `userNotificationCenter(_:didReceive:)`

#### `Frontend/iOS/Cookey/main.swift`

On iOS only:

```swift
@UIApplicationDelegateAdaptor(CookeyAppDelegate.self) private var appDelegate
```

Wire the shared `PushRegistrationCoordinator` into both the app delegate and the `SessionUploadModel`.

### 6.3 APN opt-in UI

#### `Frontend/iOS/Cookey/Interface/APNConsentView.swift`

Prompt after the first successful upload per relay origin.

Prompt key:

```text
apn_prompt_state::<serverURL.absoluteString>
```

Store one of:

- `accepted`
- `declined`

Do not prompt repeatedly after a user has already answered for that relay.

### 6.4 Server-side registration storage

#### `Server/Sources/Server/Models.swift`

Add:

```swift
public struct APNRegistration: Codable, Sendable {
    public let deviceID: String
    public let token: String
    public let environment: String
    public let registeredAt: Date
    public let updatedAt: Date
}
```

Add an APNs config model:

```swift
public struct APNSConfiguration: Sendable {
    public let teamID: String
    public let keyID: String
    public let bundleID: String
    public let privateKeyPath: String
}
```

#### `Server/Sources/Server/Storage.swift`

Extend `RequestStorage` with:

```swift
private var apnRegistrations: [String: APNRegistration] = [:]

public func storeAPNRegistration(...)
public func apnRegistration(deviceID: String) -> APNRegistration?
public func removeAPNRegistration(deviceID: String)
```

Important:

- APN registrations are durable in memory for the life of the relay process
- they are not tied to the 300-second request TTL
- replace the existing token when the same `deviceID` re-registers
- remove the token only on explicit unregister or APNs invalid-token responses

### 6.5 Server API

#### `Server/Sources/Server/Routes.swift`

Add:

```text
POST   /v1/devices/:device_id/apn-token
DELETE /v1/devices/:device_id/apn-token
```

`POST` body:

```json
{ "token": "<hex>", "environment": "sandbox" | "production" }
```

Behavior:

- upsert registration in storage
- return `201 Created`

`DELETE` behavior:

- remove the registration if present
- return `204 No Content`

### 6.6 Push delivery at request creation

Do not invent a second CLI `notify` endpoint. The relay already sees the whole login request during `POST /v1/requests`.

#### `Server/Sources/Server/Routes.swift` — `createRequest`

After storing the request:

1. look up `apnRegistration(deviceID: loginRequest.deviceID)`
2. if absent, continue normally
3. if present and APNs config exists, fire a non-blocking task to send a push
4. never fail request creation because push delivery failed

This keeps notification delivery server-driven and removes an unnecessary extra round trip from the CLI.

### 6.7 APNs client

#### `Server/Sources/Server/APNSClient.swift`

Add a small APNs client using existing `swift-crypto` plus `URLSession`.

Responsibilities:

- read the `.p8` key from disk
- build ES256 JWT bearer tokens with `P256.Signing.PrivateKey`
- cache the signed token for about 50 minutes
- send HTTP/2 requests to:
  - `https://api.sandbox.push.apple.com`
  - `https://api.push.apple.com`
- remove invalid registrations on permanent APNs token errors

Notification payload:

```json
{
  "aps": {
    "alert": {
      "title": "Cookey login request",
      "body": "Approve login for https://example.com"
    },
    "sound": "default"
  },
  "rid": "...",
  "server_url": "https://relay.example.com",
  "target_url": "https://example.com",
  "pubkey": "...",
  "device_id": "..."
}
```

That payload is sufficient for the app to reconstruct the same `DeepLink` it would have received from the QR code.

### 6.8 Server configuration

#### `Server/Sources/Server/main.swift`

Load optional APNs configuration from environment:

- `COOKEY_APNS_TEAM_ID`
- `COOKEY_APNS_KEY_ID`
- `COOKEY_APNS_BUNDLE_ID`
- `COOKEY_APNS_PRIVATE_KEY_PATH`

If any are missing, start the relay normally with APNs disabled.

This keeps local development simple and keeps APNs opt-in at deployment time.

---

## 7. File Change Summary

### CLI

| File | Change |
|------|--------|
| `CLI/Sources/CLI/main.swift` | Add `export` command, handler, flags, usage, and `PlaywrightStorageState` |
| `CLI/Sources/Core/Config.swift` | Add `deviceIdentifier` path and load/create helper; extend `BootstrapContext` |
| `CLI/Sources/Core/Models.swift` | Add `deviceID` to `LoginManifest` and `RelayRegisterRequest` |
| `CLI/Sources/Core/QRCode.swift` | Add `device_id` query item |
| `CLI/Sources/Core/RelayClient.swift` | Include `device_id` during request registration |
| `CLI/Sources/Core/KeyManager.swift` | Replace in-file crypto implementation with shared package import |
| `CLI/Package.swift` | Add local package dependency on `../Packages/CryptoBox` |

### Shared package

| File | Change |
|------|--------|
| `Packages/CryptoBox/Package.swift` | New cross-platform package definition |
| `Packages/CryptoBox/Sources/CryptoBox/XSalsa20Poly1305Box.swift` | New shared `open` and `seal` implementation plus `CryptoBoxError` |

### Server

| File | Change |
|------|--------|
| `Server/Sources/Server/Models.swift` | Add `deviceID` to request models, `APNRegistration`, `APNSConfiguration` |
| `Server/Sources/Server/Storage.swift` | Add durable APN registration map and CRUD methods |
| `Server/Sources/Server/Routes.swift` | Add APN registration endpoints and push dispatch from `createRequest` |
| `Server/Sources/Server/APNSClient.swift` | New APNs delivery client |
| `Server/Sources/Server/main.swift` | Load optional APNs configuration |

### iOS

| File | Change |
|------|--------|
| `Frontend/iOS/Cookey.xcodeproj/project.pbxproj` | Point target at checked-in Info.plist and add local package dependency |
| `Frontend/iOS/Cookey/Resources/Info.plist` | New explicit app Info.plist with URL types and camera usage string |
| `Frontend/iOS/Cookey/Backend/AppEnvironment.swift` | Add `current` URL override |
| `Frontend/iOS/Cookey/Backend/APIClient.swift` | Add session-upload and APN registration methods |
| `Frontend/iOS/Cookey/Backend/HealthCheckModel.swift` | Default client from `AppEnvironment.current` |
| `Frontend/iOS/Cookey/Backend/DeepLink.swift` | New deep-link parser |
| `Frontend/iOS/Cookey/Backend/Models.swift` | New upload/capture wire models |
| `Frontend/iOS/Cookey/Backend/SessionUploadModel.swift` | New phase-driven scan/open/upload state machine |
| `Frontend/iOS/Cookey/Backend/PushRegistrationCoordinator.swift` | New iOS push-registration and notification-routing coordinator |
| `Frontend/iOS/Cookey/CookeyAppDelegate.swift` | New iOS app delegate bridge for APNs callbacks |
| `Frontend/iOS/Cookey/main.swift` | Wire scene URL handling, app delegate, push coordinator, and session model |
| `Frontend/iOS/Cookey/Interface/ContentView.swift` | Replace placeholder flow with model-driven sheet |
| `Frontend/iOS/Cookey/Interface/ScannerView.swift` | New iOS-only QR scanner |
| `Frontend/iOS/Cookey/Interface/InAppBrowserView.swift` | New isolated `WKWebView` capture flow |
| `Frontend/iOS/Cookey/Interface/UploadProgressView.swift` | New upload status UI |
| `Frontend/iOS/Cookey/Interface/APNConsentView.swift` | New opt-in notifications prompt |

---

## 8. Verification

### CLI export

```bash
cd CLI
mkdir -p ~/.cookey/sessions
cat > ~/.cookey/sessions/r_test.json <<'EOF'
{
  "cookies": [],
  "origins": [],
  "_cookey": {
    "rid": "r_test",
    "received_at": "2026-03-31T00:00:00Z",
    "server_url": "http://localhost:5800",
    "target_url": "https://example.com",
    "device_fingerprint": "abc"
  }
}
EOF

swift run cookey export
swift run cookey export r_test --out /tmp/state.json --pretty
grep '_cookey' /tmp/state.json && false || true
```

Expected:

- stdout/file contain only `cookies` and `origins`
- nonexistent RID exits with code 1

### Shared package + CLI build

```bash
cd Packages/CryptoBox && swift build
cd /Users/qaq/Documents/GitHub/HelpMeIn/CLI && swift build
```

Expected:

- shared package builds on its own
- CLI builds against the shared package

### iOS simulator

```bash
xcrun simctl openurl booted "cookey://login?rid=test&server=http%3A%2F%2Flocalhost%3A5800&target=https%3A%2F%2Fexample.com&pubkey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D&device_id=test-device"
```

Expected:

- app opens
- app enters browsing phase
- deep-link path works without camera

### iOS physical device

Expected:

- scanning a QR code opens the browser flow
- `Transfer Session` uploads encrypted session successfully
- first successful upload prompts for notification opt-in

### macOS / non-iOS app targets

Expected:

- build succeeds without compiling `ScannerView`
- app still handles `cookey://` links
- no camera entitlement changes are required

### Local relay

With `COOKEY_API_URL=http://localhost:5800`:

- `HealthCheckModel()` hits the local relay by default
- session upload targets the `server` value carried in the deep link

### APNs

Physical iPhone only:

1. Upload a session once and accept notification opt-in
2. Verify relay receives `POST /v1/devices/:device_id/apn-token`
3. Run `cookey login https://example.com`
4. Verify relay creates the request and attempts APNs delivery without a second CLI notify call
5. Tap the notification
6. Verify the app reconstructs the login request and opens the browser flow
