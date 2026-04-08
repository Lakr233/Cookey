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
        $0.text = String(localized: "Bridge your AI agents with any website securely.")
        $0.font = .preferredFont(forTextStyle: .subheadline)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private lazy var howToUseButton = UIButton(type: .system).then {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "How to use")
        config.image = UIImage(systemName: "questionmark.circle.fill")
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.baseForegroundColor = .systemBlue
        
        let titleAttr = AttributeContainer([
            .font: UIFont.systemFont(ofSize: 14, weight: .medium)
        ])
        config.attributedTitle = AttributedString(config.title!, attributes: titleAttr)
        
        $0.configuration = config
        $0.addTarget(self, action: #selector(showHowToUseTapped), for: .touchUpInside)
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

    private lazy var websiteButton = UIButton(type: .system).then {
        let title = String(localized: "Made with love @ cookey.sh")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .footnote),
            .foregroundColor: UIColor.secondaryLabel.withAlphaComponent(0.5),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        $0.setAttributedTitle(NSAttributedString(string: title, attributes: attributes), for: .normal)
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.addTarget(self, action: #selector(websiteTapped), for: .touchUpInside)
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
                  let pairKeyLink = PairKeyDeepLink(url: url)
            else { return }
            Logger.push.infoFile("Prompting user to start queued request for pair key \(pairKeyLink.pairKey)")

            let title = String(localized: "New Login Request")
            let message = String(localized: "A login request was received. Would you like to start?")

            let alert = AlertViewController(title: title, message: message) { [weak self] context in
                context.addAction(title: String(localized: "Start"), attribute: .dangerous) {
                    context.dispose {
                        Logger.push.infoFile("User accepted queued push request for pair key \(pairKeyLink.pairKey)")
                        self?.sessionModel.handleURL(url)
                    }
                }
            }
            self.present(alert, animated: true)
        }
    }

    private func setupLayout() {
        let buttonStack = UIStackView(arrangedSubviews: [scanButton, typeButton]).then {
            $0.axis = .horizontal
            $0.distribution = .fillEqually
            $0.spacing = 12
        }

        let stack = UIStackView(arrangedSubviews: [
            iconView, 
            titleLabel, 
            subtitleLabel, 
            howToUseButton
        ]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 16
            
            $0.setCustomSpacing(24, after: iconView)
            $0.setCustomSpacing(12, after: titleLabel)
            $0.setCustomSpacing(8, after: subtitleLabel)
        }

        view.addSubview(stack)
        view.addSubview(websiteButton)
        view.addSubview(buttonStack)

        buttonStack.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.bottom.equalTo(websiteButton.snp.top).offset(-16)
            $0.height.equalTo(52)
        }

        websiteButton.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
        }

        stack.snp.makeConstraints {
            $0.centerY.equalToSuperview().offset(-40) // slightly above center to balance the bottom buttons
            $0.leading.trailing.equalToSuperview().inset(32)
        }
    }

    @objc private func showHowToUseTapped() {
        Logger.ui.infoFile("Opening how to use (Welcome) from home screen")
        let vc = WelcomePageViewController.makePresentedController()
        present(vc, animated: true)
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
        Logger.ui.infoFile("Enter pair key tapped")
        let alert = AlertInputViewController(
            title: String(localized: "Enter Pair Key"),
            message: String(localized: "Enter the pair key shown in your terminal."),
            placeholder: "XXXX-XXXX",
            text: "",
            cancelButtonText: String(localized: "Cancel"),
            doneButtonText: String(localized: "Submit")
        ) { [weak self] text in
            self?.sessionModel.handleManualPairKey(text)
        }
        present(alert, animated: true)
    }

    @objc private func websiteTapped() {
        guard let url = URL(string: "https://cookey.sh") else { return }
        UIApplication.shared.open(url)
    }
}
