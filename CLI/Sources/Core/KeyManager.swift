import Crypto
import CryptoBox
import Foundation

public enum KeyManagerError: Error, LocalizedError {
    case invalidAlgorithm(String)
    case invalidPrivateKey
    case invalidPublicKey
    case invalidEphemeralPublicKey
    case invalidNonce
    case invalidCiphertext
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case let .invalidAlgorithm(value):
            "Unsupported key algorithm: \(value)"
        case .invalidPrivateKey:
            "Invalid Ed25519 private key"
        case .invalidPublicKey:
            "Invalid Ed25519 public key"
        case .invalidEphemeralPublicKey:
            "Invalid X25519 ephemeral public key"
        case .invalidNonce:
            "Invalid XSalsa20 nonce"
        case .invalidCiphertext:
            "Invalid ciphertext payload"
        case .decryptionFailed:
            "Unable to decrypt session payload"
        }
    }
}

public enum KeyManager {
    public static func loadOrCreate(at url: URL) throws -> KeypairFile {
        if FileManager.default.fileExists(atPath: url.path) {
            return try ConfigStore.readJSON(KeypairFile.self, from: url)
        }

        let keypair = try generate()
        try ConfigStore.writeJSON(keypair, to: url, permissions: 0o600)
        return keypair
    }

    public static func generate() throws -> KeypairFile {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        return KeypairFile(
            version: 1,
            algorithm: "ed25519",
            publicKey: publicKey.rawRepresentation.base64EncodedString(),
            privateKey: privateKey.rawRepresentation.base64EncodedString(),
            createdAt: Date()
        )
    }

    public static func ed25519PrivateKey(from keypair: KeypairFile) throws -> Curve25519.Signing.PrivateKey {
        guard keypair.algorithm == "ed25519" else {
            throw KeyManagerError.invalidAlgorithm(keypair.algorithm)
        }

        guard let raw = Data(base64Encoded: keypair.privateKey) else {
            throw KeyManagerError.invalidPrivateKey
        }

        return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }

    public static func ed25519PublicKey(from keypair: KeypairFile) throws -> Curve25519.Signing.PublicKey {
        guard keypair.algorithm == "ed25519" else {
            throw KeyManagerError.invalidAlgorithm(keypair.algorithm)
        }

        guard let raw = Data(base64Encoded: keypair.publicKey) else {
            throw KeyManagerError.invalidPublicKey
        }

        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    public static func x25519PrivateKey(from keypair: KeypairFile) throws -> Curve25519.KeyAgreement.PrivateKey {
        let signingKey = try ed25519PrivateKey(from: keypair)
        let digest = SHA512.hash(data: signingKey.rawRepresentation)
        var scalar = Array(digest.prefix(32))
        scalar[0] &= 248
        scalar[31] &= 127
        scalar[31] |= 64
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(scalar))
    }

    public static func x25519PublicKeyBase64(from keypair: KeypairFile) throws -> String {
        let key = try x25519PrivateKey(from: keypair)
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func decryptSessionEnvelope(
        _ envelope: EncryptedSessionEnvelope,
        using keypair: KeypairFile
    ) throws -> Data {
        let algorithm = envelope.algorithm.stringValue.lowercased()
        let expectedAlgorithm = SessionEncryptionAlgorithm.x25519XSalsa20Poly1305.stringValue.lowercased()
        guard algorithm == expectedAlgorithm else {
            throw KeyManagerError.invalidAlgorithm(algorithm)
        }

        guard let ephemeralData = Data(base64Encoded: envelope.ephemeralPublicKey) else {
            throw KeyManagerError.invalidEphemeralPublicKey
        }
        guard let nonceData = Data(base64Encoded: envelope.nonce), nonceData.count == 24 else {
            throw KeyManagerError.invalidNonce
        }
        guard let ciphertextData = Data(base64Encoded: envelope.ciphertext), ciphertextData.count >= 16 else {
            throw KeyManagerError.invalidCiphertext
        }

        let privateKey = try x25519PrivateKey(from: keypair)
        let publicKey: Curve25519.KeyAgreement.PublicKey
        do {
            publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralData)
        } catch {
            throw KeyManagerError.invalidEphemeralPublicKey
        }

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let sharedKey = sharedSecret.withUnsafeBytes { Data($0) }
        do {
            return try XSalsa20Poly1305Box.open(
                ciphertext: ciphertextData,
                nonce: nonceData,
                sharedSecret: sharedKey
            )
        } catch let error as CryptoBoxError {
            throw mapCryptoBoxError(error)
        }
    }

    public static func generateRequestID() -> String {
        let bytes = (0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }
        return "r_\(Data(bytes).base64URLEncodedString())"
    }

    private static func mapCryptoBoxError(_ error: CryptoBoxError) -> KeyManagerError {
        switch error {
        case .invalidNonce:
            .invalidNonce
        case .invalidCiphertext:
            .invalidCiphertext
        case .authenticationFailed:
            .decryptionFailed
        case .invalidEphemeralPublicKey:
            .invalidEphemeralPublicKey
        case .invalidRecipientPublicKey, .randomGenerationFailed:
            .decryptionFailed
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
