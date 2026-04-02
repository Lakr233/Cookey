import AlertController
import Combine
import SnapKit
import Then
import UIKit

class HomeViewController: UIViewController {
    private let sessionModel: SessionUploadModel

    private let iconView = UIImageView().then {
        $0.image = UIImage(systemName: "qrcode.viewfinder")
        $0.tintColor = .label
        $0.contentMode = .scaleAspectFit
        $0.preferredSymbolConfiguration = .init(pointSize: 88, weight: .ultraLight)
    }

    private let titleLabel = UILabel().then {
        $0.text = String(localized: "Cookey")
        $0.font = .systemFont(ofSize: 28, weight: .bold)
        $0.textAlignment = .center
    }

    private let subtitleLabel = UILabel().then {
        $0.text = String(localized: "Scan or enter the pair code from your terminal\nto transfer a login session.")
        $0.font = .preferredFont(forTextStyle: .subheadline)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private lazy var scanButton = UIButton(configuration: .filled()).then {
        #if targetEnvironment(macCatalyst)
            $0.configuration?.title = String(localized: "Paste Link")
            $0.configuration?.image = UIImage(systemName: "doc.on.clipboard")
        #else
            $0.configuration?.title = String(localized: "Scan")
            $0.configuration?.image = UIImage(systemName: "qrcode.viewfinder")
        #endif
        $0.configuration?.imagePadding = 8
        $0.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
    }

    private lazy var typeButton = UIButton(configuration: .filled()).then {
        $0.configuration?.title = String(localized: "Enter")
        $0.configuration?.image = UIImage(systemName: "keyboard")
        $0.configuration?.imagePadding = 8
        $0.addTarget(self, action: #selector(typeTapped), for: .touchUpInside)
    }

    init(sessionModel: SessionUploadModel) {
        self.sessionModel = sessionModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.ui.infoFile("HomeViewController loaded")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        setupLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPendingNotification()
    }

    private func checkPendingNotification() {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        guard let coordinator = appDelegate?.pushCoordinator else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard let url = coordinator.consumePendingNotification(),
                  let deepLink = DeepLink(url: url)
            else { return }
            Logger.push.infoFile("Prompting user to start queued \(deepLink.requestType.rawValue) request for rid \(deepLink.rid)")

            let targetHost = deepLink.targetURL.host() ?? deepLink.targetURL.absoluteString
            let isRefresh = deepLink.requestType == .refresh
            let title = isRefresh
                ? String(localized: "New Session Refresh")
                : String(localized: "New Login Request")
            let message = isRefresh
                ? String(format: String(localized: "A session refresh was received for %@. Would you like to start?"), targetHost)
                : String(format: String(localized: "A login request was received for %@. Would you like to start?"), targetHost)

            let alert = AlertViewController(title: title, message: message) { [weak self] context in
                context.addAction(title: String(localized: "Start"), attribute: .dangerous) {
                    context.dispose {
                        Logger.push.infoFile("User accepted queued push request for rid \(deepLink.rid)")
                        self?.sessionModel.handleURL(url)
                    }
                }
            }
            self.present(alert, animated: true)
        }
    }

    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 8
            $0.setCustomSpacing(24, after: iconView)
        }

        let buttonStack = UIStackView(arrangedSubviews: [scanButton, typeButton]).then {
            $0.axis = .horizontal
            $0.distribution = .fillEqually
            $0.spacing = 12
        }

        view.addSubview(stack)
        view.addSubview(buttonStack)

        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        buttonStack.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            $0.height.equalTo(50)
        }
    }

    @objc private func settingsTapped() {
        Logger.ui.infoFile("Opening settings from home screen")
        let settings = SettingsViewController()
        navigationController?.pushViewController(settings, animated: true)
    }

    @objc private func scanTapped() {
        #if targetEnvironment(macCatalyst)
            Logger.ui.infoFile("Paste Link tapped on Mac Catalyst")
            guard let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: string),
                  url.scheme?.lowercased() == "cookey"
            else {
                let alert = AlertViewController(
                    title: String(localized: "Invalid Link"),
                    message: String(localized: "No valid Cookey link found in the clipboard.")
                ) { context in
                    context.addAction(title: String(localized: "OK"), attribute: .dangerous) {
                        context.dispose()
                    }
                }
                present(alert, animated: true)
                return
            }
            sessionModel.handleURL(url)
        #else
            Logger.ui.infoFile("Scan tapped")
            sessionModel.startScan()
        #endif
    }

    @objc private func typeTapped() {
        Logger.ui.infoFile("Type pair key tapped")
        let alert = AlertInputViewController(
            title: "Enter Pair Key",
            message: "Enter the pair key shown in your terminal.",
            placeholder: "XXXX-XXXX",
            text: "",
            cancelButtonText: "Cancel",
            doneButtonText: "Submit"
        ) { [weak self] text in
            self?.sessionModel.handleManualPairKey(text)
        }
        present(alert, animated: true)
    }
}
