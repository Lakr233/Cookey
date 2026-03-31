import Foundation
#if canImport(Dispatch)
import Dispatch
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RelayClientError: Error, LocalizedError {
    case invalidServerURL(String)
    case invalidResponse
    case httpStatus(Int, String)
    case expired(String)
    case missing(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL(let value):
            return "Invalid Relay server URL: \(value)"
        case .invalidResponse:
            return "Relay server returned an invalid response"
        case .httpStatus(let code, let body):
            return "Relay server responded with HTTP \(code): \(body)"
        case .expired(let rid):
            return "Request \(rid) expired before a session arrived"
        case .missing(let rid):
            return "Request \(rid) was not found"
        case .timeout(let rid):
            return "Timed out while waiting for session \(rid)"
        }
    }
}

public struct RelayClient {
    public let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? URLSession(configuration: .default)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func register(manifest: LoginManifest) throws {
        let url = baseURL.appendingPathComponent("v1/requests")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RelayRegisterRequest(
            rid: manifest.rid,
            targetURL: manifest.targetURL,
            cliPublicKey: manifest.cliPublicKey,
            deviceID: manifest.deviceID,
            deviceFingerprint: manifest.deviceFingerprint,
            expiresAt: manifest.expiresAt
        )
        request.httpBody = try encoder.encode(body)

        _ = try send(request)
    }

    public func fetchStatus(rid: String) throws -> RelayStatusResponse? {
        let url = baseURL.appendingPathComponent("v1/requests/\(rid)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try send(request, acceptNotFound: true)
        if response.statusCode == 404 {
            return nil
        }

        return try decoder.decode(RelayStatusResponse.self, from: data)
    }

    public func waitForSession(rid: String, transport: Transport, timeoutSeconds: Int) throws -> EncryptedSessionEnvelope {
        switch transport {
        case .poll:
            return try waitWithPolling(rid: rid, timeoutSeconds: timeoutSeconds)
        case .ws:
            // URLSession WebSocket support varies across Swift runtime environments.
            // Polling is used as the portable fallback until a server-compatible WS
            // implementation is added and verified in this package.
            return try waitWithPolling(rid: rid, timeoutSeconds: timeoutSeconds)
        }
    }

    private func waitWithPolling(rid: String, timeoutSeconds: Int) throws -> EncryptedSessionEnvelope {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while Date() < deadline {
            let remaining = max(1, Int(deadline.timeIntervalSinceNow.rounded(.down)))
            let perRequestTimeout = min(30, remaining)
            let endpoint = baseURL.appendingPathComponent("v1/requests/\(rid)/wait")

            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "timeout", value: String(perRequestTimeout))
            ]

            guard let url = components?.url else {
                throw RelayClientError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = TimeInterval(perRequestTimeout + 5)

            let (data, response) = try send(request, acceptNoContent: true, acceptNotFound: true)

            switch response.statusCode {
            case 204:
                continue
            case 404:
                throw RelayClientError.missing(rid)
            case 200 ..< 300:
                let waitResponse = try decoder.decode(RelayWaitResponse.self, from: data)
                switch waitResponse.status.lowercased() {
                case "waiting", "pending":
                    continue
                case "expired":
                    throw RelayClientError.expired(rid)
                case "ready":
                    if let envelope = waitResponse.encryptedSession {
                        return envelope
                    }
                    throw RelayClientError.invalidResponse
                default:
                    throw RelayClientError.invalidResponse
                }
            default:
                throw RelayClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }

        throw RelayClientError.timeout(rid)
    }

    private func send(
        _ request: URLRequest,
        acceptNoContent: Bool = false,
        acceptNotFound: Bool = false
    ) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseObject: URLResponse?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseObject = response
            responseError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let responseError {
            throw responseError
        }

        guard let httpResponse = responseObject as? HTTPURLResponse else {
            throw RelayClientError.invalidResponse
        }

        let data = responseData ?? Data()
        if (200 ..< 300).contains(httpResponse.statusCode) {
            return (data, httpResponse)
        }

        if acceptNoContent && httpResponse.statusCode == 204 {
            return (data, httpResponse)
        }

        if acceptNotFound && httpResponse.statusCode == 404 {
            return (data, httpResponse)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        throw RelayClientError.httpStatus(httpResponse.statusCode, body)
    }
}
