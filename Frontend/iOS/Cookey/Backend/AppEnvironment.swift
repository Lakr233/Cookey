import Foundation

enum AppEnvironment {
    static let productionAPIBaseURL = URL(string: "https://api.cookey.sh")!

    static var current: URL {
        if let override = ProcessInfo.processInfo.environment["COOKEY_API_URL"],
           let url = URL(string: override)
        {
            return url
        }
        return productionAPIBaseURL
    }
}
