import Foundation

public enum Transport: String, Codable, CaseIterable {
    case ws
    case poll
}

public enum DaemonState: String, Codable, CaseIterable {
    case waiting
    case receiving
    case ready
    case expired
    case error
}

public enum CLIStatus: String, Codable {
    case waiting
    case receiving
    case ready
    case expired
    case orphaned
    case error
    case missing
}

public struct KeypairFile: Codable {
    public let version: Int
    public let algorithm: String
    public let publicKey: String
    public let privateKey: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case algorithm
        case publicKey = "public_key"
        case privateKey = "private_key"
        case createdAt = "created_at"
    }

    public init(version: Int, algorithm: String, publicKey: String, privateKey: String, createdAt: Date) {
        self.version = version
        self.algorithm = algorithm
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.createdAt = createdAt
    }
}

public struct AppConfig: Codable {
    public let defaultServer: String?
    public let transport: Transport?
    public let timeoutSeconds: Int?
    public let sessionRetentionDays: Int?

    enum CodingKeys: String, CodingKey {
        case defaultServer = "default_server"
        case transport
        case timeoutSeconds = "timeout_seconds"
        case sessionRetentionDays = "session_retention_days"
    }

    public init(
        defaultServer: String? = nil,
        transport: Transport? = nil,
        timeoutSeconds: Int? = nil,
        sessionRetentionDays: Int? = nil
    ) {
        self.defaultServer = defaultServer
        self.transport = transport
        self.timeoutSeconds = timeoutSeconds
        self.sessionRetentionDays = sessionRetentionDays
    }
}

public struct LoginManifest: Codable {
    public let rid: String
    public let targetURL: String
    public let serverURL: String
    public let cliPublicKey: String
    public let deviceFingerprint: String
    public let transportHint: Transport
    public let createdAt: Date
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case rid
        case targetURL = "target_url"
        case serverURL = "server_url"
        case cliPublicKey = "cli_public_key"
        case deviceFingerprint = "device_fingerprint"
        case transportHint = "transport_hint"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    public init(
        rid: String,
        targetURL: String,
        serverURL: String,
        cliPublicKey: String,
        deviceFingerprint: String,
        transportHint: Transport,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.rid = rid
        self.targetURL = targetURL
        self.serverURL = serverURL
        self.cliPublicKey = cliPublicKey
        self.deviceFingerprint = deviceFingerprint
        self.transportHint = transportHint
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct DaemonDescriptor: Codable {
    public let rid: String
    public let pid: Int32
    public let ppid: Int32
    public let status: DaemonState
    public let serverURL: String
    public let transport: Transport
    public let startedAt: Date
    public let updatedAt: Date
    public let targetURL: String
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case rid
        case pid
        case ppid
        case status
        case serverURL = "server_url"
        case transport
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case targetURL = "target_url"
        case errorMessage = "error_message"
    }

    public init(
        rid: String,
        pid: Int32,
        ppid: Int32,
        status: DaemonState,
        serverURL: String,
        transport: Transport,
        startedAt: Date,
        updatedAt: Date,
        targetURL: String,
        errorMessage: String? = nil
    ) {
        self.rid = rid
        self.pid = pid
        self.ppid = ppid
        self.status = status
        self.serverURL = serverURL
        self.transport = transport
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.targetURL = targetURL
        self.errorMessage = errorMessage
    }

    public func updating(status: DaemonState, errorMessage: String? = nil) -> DaemonDescriptor {
        DaemonDescriptor(
            rid: rid,
            pid: pid,
            ppid: ppid,
            status: status,
            serverURL: serverURL,
            transport: transport,
            startedAt: startedAt,
            updatedAt: Date(),
            targetURL: targetURL,
            errorMessage: errorMessage
        )
    }
}

public struct RelayRegisterRequest: Codable {
    public let rid: String
    public let targetURL: String
    public let cliPublicKey: String
    public let deviceFingerprint: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case rid
        case targetURL = "target_url"
        case cliPublicKey = "cli_public_key"
        case deviceFingerprint = "device_fingerprint"
        case expiresAt = "expires_at"
    }
}

public struct RelayStatusResponse: Codable {
    public let rid: String?
    public let status: String?
    public let targetURL: String?
    public let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case rid
        case status
        case targetURL = "target_url"
        case expiresAt = "expires_at"
    }
}

public struct RelayWaitResponse: Codable {
    public let rid: String?
    public let status: String
    public let session: EncryptedSessionEnvelope?
    public let payload: EncryptedSessionEnvelope?
}

public struct EncryptedSessionEnvelope: Codable {
    public let version: Int
    public let algorithm: String
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

public struct SessionFile: Codable {
    public let cookies: [BrowserCookie]
    public let origins: [OriginState]
    public let metadata: SessionMetadata?

    enum CodingKeys: String, CodingKey {
        case cookies
        case origins
        case metadata = "_helpmein"
    }
}

public struct BrowserCookie: Codable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expires: Double
    public let httpOnly: Bool
    public let secure: Bool
    public let sameSite: String

    enum CodingKeys: String, CodingKey {
        case name
        case value
        case domain
        case path
        case expires
        case httpOnly = "httpOnly"
        case secure
        case sameSite = "sameSite"
    }
}

public struct OriginState: Codable {
    public let origin: String
    public let localStorage: [OriginStorageItem]
}

public struct OriginStorageItem: Codable {
    public let name: String
    public let value: String
}

public struct SessionMetadata: Codable {
    public let rid: String
    public let receivedAt: Date
    public let serverURL: String
    public let targetURL: String
    public let deviceFingerprint: String

    enum CodingKeys: String, CodingKey {
        case rid
        case receivedAt = "received_at"
        case serverURL = "server_url"
        case targetURL = "target_url"
        case deviceFingerprint = "device_fingerprint"
    }
}

public struct StatusSnapshot: Codable {
    public let rid: String
    public let status: CLIStatus
    public let pid: Int32?
    public let targetURL: String?
    public let sessionPath: String?
    public let updatedAt: Date?
    public let serverURL: String?
    public let transport: Transport?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case rid
        case status
        case pid
        case targetURL = "target_url"
        case sessionPath = "session_path"
        case updatedAt = "updated_at"
        case serverURL = "server_url"
        case transport
        case errorMessage = "error_message"
    }
}
