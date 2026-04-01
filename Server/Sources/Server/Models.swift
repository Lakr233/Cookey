import Foundation

/// Request ID type
public typealias RequestID = String

/// Request status
public enum RequestStatus: String, Codable, Sendable {
    case pending
    case ready
    case expired
    case delivered
}

/// Login request manifest from CLI
public struct LoginRequest: Codable, Sendable {
    public let rid: RequestID
    public let targetUrl: String
    public let cliPublicKey: String
    public let deviceID: String
    public let deviceFingerprint: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case rid
        case targetUrl = "target_url"
        case cliPublicKey = "cli_public_key"
        case deviceID = "device_id"
        case deviceFingerprint = "device_fingerprint"
        case expiresAt = "expires_at"
    }
}

/// Stored request with metadata
public struct StoredRequest: Codable, Sendable {
    public let rid: RequestID
    public let targetUrl: String
    public let cliPublicKey: String
    public let deviceID: String
    public let deviceFingerprint: String
    public let createdAt: Date
    public let expiresAt: Date
    public var status: RequestStatus
    public var encryptedSession: EncryptedSession?

    public init(from request: LoginRequest, status: RequestStatus = .pending) {
        rid = request.rid
        targetUrl = request.targetUrl
        cliPublicKey = request.cliPublicKey
        deviceID = request.deviceID
        deviceFingerprint = request.deviceFingerprint
        createdAt = Date()
        expiresAt = request.expiresAt
        self.status = status
        encryptedSession = nil
    }
}

/// Encrypted session payload from mobile
public enum SessionEncryptionAlgorithm: String, Codable, CaseIterable, Sendable, CustomStringConvertible {
    case x25519XSalsa20Poly1305 = "x25519-xsalsa20poly1305"

    public var stringValue: String {
        rawValue
    }

    public var description: String {
        rawValue
    }

    public init?(stringValue: String) {
        guard let algorithm = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(stringValue) == .orderedSame
        }) else {
            return nil
        }

        self = algorithm
    }
}

public struct EncryptedSession: Codable, Sendable {
    public let version: Int
    public let algorithm: SessionEncryptionAlgorithm
    public let ephemeralPublicKey: String
    public let nonce: String
    public let ciphertext: String
    public let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case algorithm
        case ephemeralPublicKey = "ephemeral_public_key"
        case nonce
        case ciphertext
        case capturedAt = "captured_at"
    }
}

public struct APNRegistration: Codable, Sendable {
    public let deviceID: String
    public let token: String
    public let environment: String
    public let registeredAt: Date
    public let updatedAt: Date
}

public struct APNSConfiguration: Sendable {
    public let teamID: String
    public let keyID: String
    public let bundleID: String
    public let privateKeyPath: String
}

public struct APNTokenRegistrationRequest: Codable, Sendable {
    public let token: String
    public let environment: String
}

/// Request status response
public struct RequestStatusResponse: Codable, Sendable {
    public let rid: RequestID
    public let status: RequestStatus
    public let targetUrl: String
    public let expiresAt: Date
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case rid
        case status
        case targetUrl = "target_url"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    public init(from stored: StoredRequest) {
        rid = stored.rid
        status = stored.status
        targetUrl = stored.targetUrl
        expiresAt = stored.expiresAt
        createdAt = stored.createdAt
    }
}

/// Long-poll wait response
public struct RequestWaitResponse: Codable, Sendable {
    public let rid: RequestID
    public let status: RequestStatus
    public let encryptedSession: EncryptedSession?
    public let deliveredAt: Date?

    enum CodingKeys: String, CodingKey {
        case rid
        case status
        case encryptedSession = "encrypted_session"
        case deliveredAt = "delivered_at"
    }

    public init(
        rid: RequestID,
        status: RequestStatus,
        encryptedSession: EncryptedSession? = nil,
        deliveredAt: Date? = nil
    ) {
        self.rid = rid
        self.status = status
        self.encryptedSession = encryptedSession
        self.deliveredAt = deliveredAt
    }

    public init(from stored: StoredRequest, deliveredAt: Date? = nil) {
        rid = stored.rid
        status = stored.status
        encryptedSession = stored.encryptedSession
        self.deliveredAt = deliveredAt
    }
}

/// WebSocket message types
public enum WebSocketMessage: Codable, Sendable {
    case status(StatusPayload)
    case session(SessionPayload)
    case error(ErrorPayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case status
        case session
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .status:
            let payload = try container.decode(StatusPayload.self, forKey: .payload)
            self = .status(payload)
        case .session:
            let payload = try container.decode(SessionPayload.self, forKey: .payload)
            self = .session(payload)
        case .error:
            let payload = try container.decode(ErrorPayload.self, forKey: .payload)
            self = .error(payload)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .status(payload):
            try container.encode(MessageType.status, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .session(payload):
            try container.encode(MessageType.session, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case let .error(payload):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

public struct StatusPayload: Codable, Sendable {
    public let status: RequestStatus
    public let timestamp: Date
}

public struct SessionPayload: Codable, Sendable {
    public let encryptedSession: EncryptedSession
    public let deliveredAt: Date

    enum CodingKeys: String, CodingKey {
        case encryptedSession = "encrypted_session"
        case deliveredAt = "delivered_at"
    }
}

public struct ErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
}

/// Server configuration
public struct ServerConfig: Sendable {
    public let host: String
    public let port: Int
    public let defaultTTL: TimeInterval
    public let maxPayloadSize: Int
    public let publicURL: String
    public let apnsConfiguration: APNSConfiguration?

    public init(
        host: String = "0.0.0.0",
        port: Int = 8080,
        defaultTTL: TimeInterval = 300,
        maxPayloadSize: Int = 1 * 1024 * 1024, // 1MB
        publicURL: String? = nil,
        apnsConfiguration: APNSConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.defaultTTL = defaultTTL
        self.maxPayloadSize = maxPayloadSize
        self.publicURL = publicURL ?? "http://\(host):\(port)"
        self.apnsConfiguration = apnsConfiguration
    }
}
