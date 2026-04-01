import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor APNSClient {
    private let configuration: APNSConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var signingKey: P256.Signing.PrivateKey?
    private var cachedBearerToken: String?
    private var cachedBearerTokenIssuedAt: Date?

    public init(configuration: APNSConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func sendLoginRequestNotification(
        request: StoredRequest,
        serverURL: String,
        registration: APNRegistration,
        storage: RequestStorage
    ) async {
        do {
            try await sendNotification(
                request: request,
                serverURL: serverURL,
                registration: registration,
                storage: storage
            )
        } catch {
        }
    }

    private func sendNotification(
        request: StoredRequest,
        serverURL: String,
        registration: APNRegistration,
        storage: RequestStorage
    ) async throws {
        let baseURL = registration.environment.lowercased() == "sandbox"
            ? URL(string: "https://api.sandbox.push.apple.com")!
            : URL(string: "https://api.push.apple.com")!
        let url = baseURL.appending(path: "/3/device/\(registration.token)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("alert", forHTTPHeaderField: "apns-push-type")
        urlRequest.setValue("10", forHTTPHeaderField: "apns-priority")
        urlRequest.setValue(configuration.bundleID, forHTTPHeaderField: "apns-topic")
        urlRequest.setValue("bearer \(try jwtToken())", forHTTPHeaderField: "authorization")
        urlRequest.httpBody = try encoder.encode(APNSNotificationPayload(request: request, serverURL: serverURL))

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APNSClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let reason = try? decoder.decode(APNSErrorResponse.self, from: data)
            if isPermanentTokenError(statusCode: httpResponse.statusCode, reason: reason?.reason) {
                await storage.removeAPNRegistration(deviceID: registration.deviceID)
            }
            throw APNSClientError.httpStatus(httpResponse.statusCode, reason?.reason ?? String(decoding: data, as: UTF8.self))
        }
    }

    private func jwtToken() throws -> String {
        let now = Date()
        if let cachedBearerToken,
           let cachedBearerTokenIssuedAt,
           now.timeIntervalSince(cachedBearerTokenIssuedAt) < (50 * 60) {
            return cachedBearerToken
        }

        let header = APNSJWTHeader(alg: "ES256", kid: configuration.keyID)
        let payload = APNSJWTPayload(
            iss: configuration.teamID,
            iat: Int(now.timeIntervalSince1970)
        )
        let headerPart = try encodedJWTPart(header)
        let payloadPart = try encodedJWTPart(payload)
        let signingInput = "\(headerPart).\(payloadPart)"
        let signature = try loadSigningKey().signature(for: Data(signingInput.utf8))
        let token = "\(signingInput).\(signature.derRepresentation.base64URLEncodedString())"

        cachedBearerToken = token
        cachedBearerTokenIssuedAt = now
        return token
    }

    private func loadSigningKey() throws -> P256.Signing.PrivateKey {
        if let signingKey {
            return signingKey
        }

        let pem = try String(contentsOfFile: configuration.privateKeyPath, encoding: .utf8)
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        signingKey = key
        return key
    }

    private func encodedJWTPart<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return data.base64URLEncodedString()
    }

    private func isPermanentTokenError(statusCode: Int, reason: String?) -> Bool {
        guard statusCode == 400 || statusCode == 410 else {
            return false
        }

        switch reason {
        case "BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered":
            return true
        default:
            return false
        }
    }
}

private enum APNSClientError: Error {
    case invalidResponse
    case httpStatus(Int, String)
}

private struct APNSNotificationPayload: Encodable {
    let aps: APSPayload
    let rid: String
    let serverURL: String
    let targetURL: String
    let pubkey: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case aps
        case rid
        case serverURL = "server_url"
        case targetURL = "target_url"
        case pubkey
        case deviceID = "device_id"
    }

    init(request: StoredRequest, serverURL: String) {
        self.aps = APSPayload(
            alert: APSAlert(
                title: "Cookey login request",
                body: "Approve login for \(request.targetUrl)"
            ),
            sound: "default"
        )
        self.rid = request.rid
        self.serverURL = serverURL
        self.targetURL = request.targetUrl
        self.pubkey = request.cliPublicKey
        self.deviceID = request.deviceID
    }
}

private struct APSPayload: Encodable {
    let alert: APSAlert
    let sound: String
}

private struct APSAlert: Encodable {
    let title: String
    let body: String
}

private struct APNSErrorResponse: Decodable {
    let reason: String
}

private struct APNSJWTHeader: Encodable {
    let alg: String
    let kid: String
}

private struct APNSJWTPayload: Encodable {
    let iss: String
    let iat: Int
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
