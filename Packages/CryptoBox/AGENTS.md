# CryptoBox

Shared Swift package providing XSalsa20-Poly1305 authenticated encryption with Curve25519 key agreement.

## Dependencies

- `apple/swift-crypto` (>=3.0.0) — Curve25519 key agreement

## Source

Single file: `Sources/CryptoBox/XSalsa20Poly1305Box.swift`

## Public API

```swift
enum XSalsa20Poly1305Box {
    static func seal(plaintext: Data, recipientPublicKey: Data) throws
        -> (ephemeralPublicKey: Data, nonce: Data, ciphertext: Data)

    static func open(ciphertext: Data, nonce: Data, sharedSecret: Data) throws
        -> Data
}

enum CryptoBoxError: Error {
    case invalidNonce, invalidCiphertext, authenticationFailed
    case invalidRecipientPublicKey, invalidEphemeralPublicKey, randomGenerationFailed
}
```

## Internals

- 32-byte keys, 24-byte nonces
- HSalsa20 key derivation, Salsa20 stream cipher, Poly1305 MAC
- Ephemeral Curve25519 keypair generated per `seal` call
- Constant-time comparison for MAC verification
- Pure Swift implementation — no C dependencies beyond swift-crypto

## Conventions

- All methods are static on an enum (no instances)
- Private helper functions, pure functional style
- Platforms: iOS 17+, macOS 13+
