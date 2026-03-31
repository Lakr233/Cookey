import Foundation

struct EncryptedSessionEnvelope: Encodable {
    let version: Int
    let algorithm: String
    let ephemeralPublicKey: String
    let nonce: String
    let ciphertext: String
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case algorithm
        case nonce
        case ciphertext
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

struct CapturedStorageItem: Encodable, Decodable, Equatable {
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
