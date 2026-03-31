#if os(iOS)
import UIKit
import UserNotifications

final class CookeyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pushCoordinator: PushRegistrationCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await pushCoordinator?.handleRegisteredDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushCoordinator?.handleRegistrationFailure(error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        pushCoordinator?.handleNotificationUserInfo(response.notification.request.content.userInfo)
        completionHandler()
    }
}
#endif
