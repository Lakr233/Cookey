import Foundation

struct APIHealthCheckResult {
    let body: String
    let serverName: String
    let checkedAt: Date
}

struct APIClient {
    let baseURL: URL

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
}
