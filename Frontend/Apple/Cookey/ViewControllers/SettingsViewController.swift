import AlertController
import ConfigurableKit
import SnapKit
import Then
import UIKit
import UserNotifications

final class SettingsViewController: StackScrollController {
    static let feedbackURL = URL(string: "https://feedback.qaq.wiki/")!

    static let defaultServerPlaceholder = defaultServerEndpoint.host() ?? "api.cookey.sh"

    static let object = ConfigurableObject(
        icon: "arrow.trianglehead.2.clockwise",
        title: "Allow Refresh Requests",
        explain: "When enabled, the relay server can send push notifications to this device for session refresh requests. This requires system notification permissions.",
        key: AppSettings.allowRefreshKey,
        defaultValue: false,
        annotation: .toggle
    )
    .whenValueChange(type: Bool.self, to: whenValueChanged)

    static let feedbackObject = ConfigurableObject(
        icon: "ellipsis.bubble",
        title: "Submit Feedback",
        explain: "Report bugs, request features, or share your thoughts about Cookey.",
        ephemeralAnnotation: .action(handler: openFeedback)
    )

    static let trustedKeysObject = ConfigurableObject(
        icon: "person.badge.key.fill",
        title: "Trusted Public Keys",
        explain: "Manage command-line public keys you have verified. Removing a key will require re-verification on the next connection.",
        ephemeralAnnotation: .action { controller in
            controller.navigationController?.pushViewController(TrustedPublicKeysViewController(), animated: true)
        }
    )

    static let logsObject = ConfigurableObject(
        icon: "doc.text.magnifyingglass",
        title: "View Logs",
        explain: "Inspect recent application logs for troubleshooting.",
        ephemeralAnnotation: .action { controller in
            controller.navigationController?.pushViewController(LogViewerController(), animated: true)
        }
    )

    init() {
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Settings")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: nil,
            action: nil
        ).then {
            $0.menu = UIMenu(children: [
                UIAction(
                    title: String(localized: "Guide"),
                    image: UIImage(systemName: "sparkles")
                ) { [weak self] _ in
                    self?.presentWhatsNew()
                },
                UIMenu(options: .displayInline, children: [
                    UIAction(
                        title: String(localized: "Privacy Policy"),
                        image: UIImage(systemName: "lock.shield")
                    ) { [weak self] _ in
                        self?.openPrivacyPolicy()
                    },
                    UIAction(
                        title: String(localized: "Open Source Licenses"),
                        image: UIImage(systemName: "flag.filled.and.flag.crossed")
                    ) { [weak self] _ in
                        self?.openOpenSourceLicenses()
                    },
                ]),
            ])
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        // MARK: - Appearance

        #if !targetEnvironment(macCatalyst)
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: String(localized: "Appearance"))
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(AppIconSettings.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())
        #endif

        // MARK: - General

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "General"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(makeDefaultServerView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(Self.object.createView())
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(Self.trustedKeysObject.createView())
        stackView.addArrangedSubview(SeparatorView())

        // MARK: - Contact Us

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Contact Us"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        for object in [Self.logsObject, Self.feedbackObject] {
            stackView.addArrangedSubviewWithMargin(object.createView())
            stackView.addArrangedSubview(SeparatorView())
        }

        buildBuildInfoFooter()
    }

    // MARK: - Default Server

    private func makeDefaultServerView() -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "server.rack"))
        view.configure(title: "Default Server")
        view.configure(
            description: "The server used when no relay is specified. HTTPS is enforced automatically."
        )

        let currentValue: String = ConfigurableKit.value(
            forKey: AppSettings.defaultServerKey,
            defaultValue: ""
        )
        view.configure(value: currentValue.isEmpty ? Self.defaultServerPlaceholder : currentValue)

        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return buildDefaultServerMenu(view: view)
        }
        return view
    }

    private func buildDefaultServerMenu(view: ConfigurableInfoView) -> [UIMenuElement] {
        let currentValue: String = ConfigurableKit.value(
            forKey: AppSettings.defaultServerKey,
            defaultValue: ""
        )

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { [weak self, weak view] _ in
            guard let self, let view else { return }
            let input = AlertInputViewController(
                title: String(localized: "Edit Default Server"),
                message: String(localized: "Enter a domain name — HTTPS is enforced automatically."),
                placeholder: Self.defaultServerPlaceholder,
                text: currentValue
            ) { [weak view] newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                ConfigurableKit.set(value: trimmed, forKey: AppSettings.defaultServerKey)
                view?.configure(value: trimmed.isEmpty ? Self.defaultServerPlaceholder : trimmed)
            }
            present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        if !currentValue.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = currentValue
            }
            menuElements.append(copyAction)
        }

        let useDefaultAction = UIAction(
            title: String(localized: "Use Default (\(Self.defaultServerPlaceholder))"),
            image: UIImage(systemName: "arrow.counterclockwise")
        ) { [weak view] _ in
            ConfigurableKit.set(value: "", forKey: AppSettings.defaultServerKey)
            view?.configure(value: Self.defaultServerPlaceholder)
        }

        menuElements.append(UIMenu(options: .displayInline, children: [useDefaultAction]))

        return menuElements
    }

    // MARK: - Menu Actions

    private func presentWhatsNew() {
        let controller = WelcomePageViewController.makePresentedController()
        present(controller, animated: true)
    }

    private func openPrivacyPolicy() {
        var text = String(localized: "Resource not found, please check your installation.")
        if let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
           let content = try? String(contentsOf: url)
        { text = content }
        let vc = TextViewerController(title: String(localized: "Privacy Policy"), text: text)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openOpenSourceLicenses() {
        var text = String(localized: "Resource not found, please check your installation.")
        if let url = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "md"),
           let content = try? String(contentsOf: url)
        { text = content }
        let vc = TextViewerController(title: String(localized: "Open Source Licenses"), text: text)
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Build Info Footer

    private func buildBuildInfoFooter() {
        let version: String = {
            let info = Bundle.main.infoDictionary
            let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            return "Version \(marketing) (\(build))"
        }()

        let label = UILabel().then {
            let lines = [
                version,
                BuildInfo.buildTime.isEmpty ? nil : BuildInfo.buildTime,
                BuildInfo.commitID.isEmpty ? nil : String(BuildInfo.commitID.prefix(7)),
            ]
            .compactMap(\.self)
            .filter { !$0.isEmpty }

            $0.text = lines.joined(separator: "\n")
            $0.font = .monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .regular
            )
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 0
        }

        let container = UIView().then {
            $0.addSubview(label)
            label.snp.makeConstraints {
                $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16))
            }
        }

        stackView.addArrangedSubview(container)
    }

    // MARK: - Notification Toggle

    @MainActor
    private static func openFeedback(_: UIViewController) async {
        Logger.ui.infoFile("Opening feedback URL from settings")
        await UIApplication.shared.open(feedbackURL)
    }

    nonisolated static func whenValueChanged(_ newValue: Bool?) -> Bool? {
        let enabled = newValue == true
        Logger.ui.infoFile("Allow Refresh Requests toggled to \(enabled)")
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Logger.push.infoFile("Notification permission already granted; registering for remote notifications")
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            case .notDetermined:
                do {
                    Logger.push.infoFile("Notification permission not determined; requesting authorization")
                    let granted = try await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    await MainActor.run {
                        if granted {
                            Logger.push.infoFile("Notification permission granted from settings flow")
                            UIApplication.shared.registerForRemoteNotifications()
                        } else if enabled {
                            Logger.push.errorFile("Notification permission denied from settings flow; resetting toggle")
                            ConfigurableKit.set(value: false, forKey: AppSettings.allowRefreshKey)
                        }
                    }
                } catch {
                    if enabled {
                        Logger.push.errorFile("Notification authorization request failed: \(error.localizedDescription)")
                        await MainActor.run {
                            ConfigurableKit.set(value: false, forKey: AppSettings.allowRefreshKey)
                        }
                    }
                }
            default:
                if enabled {
                    Logger.push.errorFile("Notifications unavailable for Cookey; resetting refresh toggle")
                    await MainActor.run {
                        ConfigurableKit.set(value: false, forKey: AppSettings.allowRefreshKey)
                    }
                }
            }
        }
        return newValue
    }
}
