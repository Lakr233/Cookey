import Then
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var flowCoordinator: FlowCoordinator?

    var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let homeVC = HomeViewController(sessionModel: appDelegate.sessionModel)
        let nav = UINavigationController(rootViewController: homeVC)

        flowCoordinator = FlowCoordinator(
            navigationController: nav,
            sessionModel: appDelegate.sessionModel
        )

        window = UIWindow(windowScene: windowScene).then {
            $0.rootViewController = nav
            $0.makeKeyAndVisible()
        }

        #if targetEnvironment(macCatalyst)
            let fixedSize = CGSize(width: 666, height: 666)
            windowScene.sizeRestrictions?.minimumSize = fixedSize
            windowScene.sizeRestrictions?.maximumSize = fixedSize
        #endif

        if let url = connectionOptions.urlContexts.first?.url {
            appDelegate.sessionModel.handleURL(url)
        }

        if WelcomeExperience.shouldPresent {
            let welcome = WelcomePageViewController.makePresentedController {
                WelcomeExperience.markPresented()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                nav.topViewController?.present(welcome, animated: true)
            }
        }

        Task { await appDelegate.pushCoordinator.attach(to: appDelegate.sessionModel) }
    }

    func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        appDelegate.sessionModel.handleURL(url)
    }
}
