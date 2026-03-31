import Foundation
import Observation

#if os(iOS)
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushRegistrationCoordinator {
    enum State: Equatable {
        case idle
        case requestingPermission
        case waitingForToken(serverURL: URL, deviceID: String)
        case uploadingToken
        case failed(String)
    }

    static let isSupported = true

    var state: State = .idle

    private weak var model: SessionUploadModel?

    func beginRegistration(serverURL: URL, deviceID: String) async {
        state = .requestingPermission

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                state = .failed("Notification permission was denied.")
                return
            }

            state = .waitingForToken(serverURL: serverURL, deviceID: deviceID)
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func handleRegisteredDeviceToken(_ token: Data) async {
        guard case .waitingForToken(let serverURL, let deviceID) = state else {
            return
        }

        state = .uploadingToken

        do {
            try await APIClient(baseURL: serverURL).registerAPNToken(
                deviceID: deviceID,
                token: token.map { String(format: "%02x", $0) }.joined(),
                environment: currentAPNEnvironment
            )
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let url = deepLinkURL(from: userInfo) else {
            return
        }

        model?.handleURL(url)
    }

    func attach(to model: SessionUploadModel) async {
        self.model = model
    }

    private var currentAPNEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard
            let rid = userInfo["rid"] as? String,
            let serverURL = userInfo["server_url"] as? String,
            let targetURL = userInfo["target_url"] as? String,
            let publicKey = userInfo["pubkey"] as? String,
            let deviceID = userInfo["device_id"] as? String
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "cookey"
        components.host = "login"
        components.queryItems = [
            URLQueryItem(name: "rid", value: rid),
            URLQueryItem(name: "server", value: serverURL),
            URLQueryItem(name: "target", value: targetURL),
            URLQueryItem(name: "pubkey", value: publicKey),
            URLQueryItem(name: "device_id", value: deviceID),
        ]
        return components.url
    }
}
#else
@MainActor
@Observable
final class PushRegistrationCoordinator {
    enum State: Equatable {
        case idle
        case failed(String)
    }

    static let isSupported = false

    var state: State = .idle

    func beginRegistration(serverURL: URL, deviceID: String) async {
    }

    func handleRegisteredDeviceToken(_ token: Data) async {
    }

    func handleRegistrationFailure(_ error: Error) {
    }

    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
    }

    func attach(to model: SessionUploadModel) async {
    }
}
#endif
