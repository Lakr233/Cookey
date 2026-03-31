import Foundation

struct DeepLink: Equatable {
    let rid: String
    let serverURL: URL
    let targetURL: URL
    let recipientPublicKeyBase64: String
    let deviceID: String

    init?(url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "cookey",
            components.host?.lowercased() == "login"
        else {
            return nil
        }

        let values: [String: String] = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            guard let value = item.value else {
                return nil
            }
            return (item.name, value.removingPercentEncoding ?? value)
        })

        guard
            let rid = values["rid"], !rid.isEmpty,
            let serverValue = values["server"], let serverURL = URL(string: serverValue),
            let targetValue = values["target"], let targetURL = URL(string: targetValue),
            let publicKey = values["pubkey"], !publicKey.isEmpty,
            let deviceID = values["device_id"], !deviceID.isEmpty
        else {
            return nil
        }

        self.rid = rid
        self.serverURL = serverURL
        self.targetURL = targetURL
        self.recipientPublicKeyBase64 = publicKey
        self.deviceID = deviceID
    }
}
