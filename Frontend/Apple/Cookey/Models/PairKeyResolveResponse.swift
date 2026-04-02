import Foundation

struct PairKeyResolveResponse: Codable {
    let rid: String
    let serverURL: String
    let targetURL: String
    let cliPublicKey: String
    let deviceID: String
    let expiresAt: Date
    let requestProof: String
    let requestSecret: String
    let requestType: String

    enum CodingKeys: String, CodingKey {
        case rid
        case serverURL = "server_url"
        case targetURL = "target_url"
        case cliPublicKey = "cli_public_key"
        case deviceID = "device_id"
        case expiresAt = "expires_at"
        case requestProof = "request_proof"
        case requestSecret = "request_secret"
        case requestType = "request_type"
    }
}
