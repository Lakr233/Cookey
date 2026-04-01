import Foundation

struct APIHealthCheckResult {
    let body: String
    let serverName: String
    let checkedAt: Date
}

struct APIClient {
    let baseURL: URL
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func healthCheck() async throws -> APIHealthCheckResult {
        let endpoint = baseURL.appending(path: "health")
        let (data, response) = try await URLSession.shared.data(from: endpoint)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "Cookey.APIClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected status code \(httpResponse.statusCode)"]
            )
        }

        return APIHealthCheckResult(
            body: String(decoding: data, as: UTF8.self),
            serverName: httpResponse.value(forHTTPHeaderField: "Server") ?? "unknown",
            checkedAt: Date()
        )
    }

    func uploadSession(rid: String, envelope: EncryptedSessionEnvelope) async throws {
        let endpoint = baseURL.appending(path: "v1/requests/\(rid)/session")
        _ = try await sendRequest(to: endpoint, method: "POST", body: envelope)
    }

    func registerAPNToken(
        deviceID: String,
        token: String,
        environment: String
    ) async throws {
        let endpoint = baseURL.appending(path: "v1/devices/\(deviceID)/apn-token")
        let body = ["token": token, "environment": environment]
        _ = try await sendRequest(to: endpoint, method: "POST", body: body)
    }

    func unregisterAPNToken(deviceID: String) async throws {
        let endpoint = baseURL.appending(path: "v1/devices/\(deviceID)/apn-token")
        _ = try await sendRequest(to: endpoint, method: "DELETE", body: String?.none)
    }

    @discardableResult
    private func sendRequest(
        to url: URL,
        method: String,
        body: (some Encodable)?
    ) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "Cookey.APIClient",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unexpected status code \(httpResponse.statusCode): \(String(decoding: data, as: UTF8.self))",
                ]
            )
        }

        return httpResponse
    }
}
