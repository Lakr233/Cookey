import Crypto
import Foundation

public enum KeyManagerError: Error, LocalizedError {
    case invalidAlgorithm(String)
    case invalidPrivateKey
    case invalidPublicKey

    public var errorDescription: String? {
        switch self {
        case .invalidAlgorithm(let value):
            return "Unsupported key algorithm: \(value)"
        case .invalidPrivateKey:
            return "Invalid Ed25519 private key"
        case .invalidPublicKey:
            return "Invalid Ed25519 public key"
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

    public static func generateRequestID() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        return "r_\(Data(bytes).base64URLEncodedString())"
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
