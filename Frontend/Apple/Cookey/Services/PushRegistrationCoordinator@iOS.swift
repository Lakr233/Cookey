import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushRegistrationCoordinator: ObservableObject {
    typealias RelayClientFactory = (URL) -> RelayClient

    enum RegistrationError: LocalizedError {
        case notificationPermissionDenied
        case notificationsUnavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notificationPermissionDenied:
                String(localized: "Notification permission was denied.")
            case .notificationsUnavailable:
                String(localized: "Notifications are disabled for Cookey on this device.")
            case .timedOut:
                String(localized: "Timed out waiting for the APNs token callback.")
            }
        }
    }

    enum State: Equatable {
        case idle
        case requestingPermission
        case waitingForToken(serverURL: URL, deviceID: String)
        case uploadingToken
        case failed(String)
    }

    static let isSupported = true

    @Published var state: State = .idle

    private weak var model: SessionUploadModel?
    private var tokenContinuation: CheckedContinuation<Void, Error>?

    init() {}

    func ensurePushToken(
        serverURL: URL,
        deviceID: String,
        requestAuthorizationIfNeeded: Bool
    ) async throws {
        _ = serverURL
        _ = deviceID
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            guard requestAuthorizationIfNeeded else {
                throw RegistrationError.notificationPermissionDenied
            }
            state = .requestingPermission
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                throw RegistrationError.notificationPermissionDenied
            }
        default:
            throw RegistrationError.notificationsUnavailable
        }

        if let token = PushTokenStore.currentToken,
           let environment = PushTokenStore.currentEnvironment
        {
            _ = token
            _ = environment
            state = .idle
            return
        }

        try await waitForTokenCallback(serverURL: serverURL, deviceID: deviceID)
    }

    func handleRegisteredDeviceToken(_ token: Data) async {
        let tokenHex = token.map { String(format: "%02x", $0) }.joined()
        PushTokenStore.currentToken = tokenHex
        PushTokenStore.currentEnvironment = currentPushEnvironment

        guard case .waitingForToken = state else {
            return
        }

        _ = tokenHex
        state = .idle
        tokenContinuation?.resume()
        tokenContinuation = nil
    }

    func handleRegistrationFailure(_ error: Error) {
        state = .failed(error.localizedDescription)
        tokenContinuation?.resume(throwing: error)
        tokenContinuation = nil
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

    private func waitForTokenCallback(serverURL: URL, deviceID: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.state = .waitingForToken(serverURL: serverURL, deviceID: deviceID)
                    self.tokenContinuation = continuation
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw RegistrationError.timedOut
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private var currentPushEnvironment: String {
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
        if let requestType = userInfo["request_type"] as? String {
            components.queryItems?.append(URLQueryItem(name: "request_type", value: requestType))
        }
        return components.url
    }
}
