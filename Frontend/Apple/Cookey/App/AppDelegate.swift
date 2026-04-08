import AlertController
import ConfigurableKit
import UIKit
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let pushCoordinator = PushRegistrationCoordinator()
    let launchBackendReachabilityCoordinator = LaunchBackendReachabilityCoordinator()
    lazy var sessionModel = SessionUploadModel(pushCoordinator: pushCoordinator)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = LogStore.shared
        Logger.app.infoFile("Application finished launching")
        UNUserNotificationCenter.current().delegate = self
        configureAlertController()
        launchBackendReachabilityCoordinator.warmUpIfNeeded()
        refreshPushTokenIfAuthorized(application)
        return true
    }

    private func refreshPushTokenIfAuthorized(_ application: UIApplication) {
        let allowed: Bool = ConfigurableKit.value(
            forKey: SettingsViewController.allowRefreshKey,
            defaultValue: false
        )
        guard allowed else {
            Logger.push.debugFile("Skipping launch APNs refresh because refresh requests are disabled")
            return
        }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else {
                Logger.push.debugFile("Skipping launch APNs refresh because authorization status is \(settings.authorizationStatus.rawValue)")
                return
            }
            Logger.push.infoFile("Refreshing APNs registration on launch")
            await MainActor.run { application.registerForRemoteNotifications() }
        }
    }

    private func configureAlertController() {
        AlertControllerConfiguration.accentColor = UIColor(named: "AccentColor") ?? .systemIndigo
        AlertControllerConfiguration.alertImage = .avatar
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SceneDelegate.self
        }
        return configuration
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Logger.push.infoFile("Received APNs device token callback with \(deviceToken.count) bytes")
        Task { await pushCoordinator.handleRegisteredDeviceToken(deviceToken) }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.push.errorFile("APNs registration failed: \(error.localizedDescription)")
        pushCoordinator.handleRegistrationFailure(error)
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Logger.push.infoFile("Foreground push notification will be presented")
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Logger.push.infoFile("User tapped push notification with keys: \(response.notification.request.content.userInfo.keys.map(String.init(describing:)).sorted())")
        pushCoordinator.handleNotificationUserInfo(response.notification.request.content.userInfo)
        completionHandler()
    }
}

private extension AppDelegate {
    /// DONT REMOVE
    static let localizationExtension: [String] = [
        String(localized: "apn_refresh_title"),
        String(localized: "apn_refresh_body"),
        String(localized: "apn_login_title"),
        String(localized: "apn_login_body"),
    ]
}
