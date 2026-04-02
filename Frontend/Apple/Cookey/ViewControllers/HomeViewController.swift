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
        $0.text = String(localized: "Scan the QR code from your terminal\nto transfer a login session.")
        $0.font = .preferredFont(forTextStyle: .subheadline)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let shadowOverlay = DappledShadowView()

    private lazy var actionButton = UIButton(configuration: .filled()).then {
        #if targetEnvironment(macCatalyst)
            $0.configuration?.title = String(localized: "Paste Link")
            $0.configuration?.image = UIImage(systemName: "doc.on.clipboard")
        #else
            $0.configuration?.title = String(localized: "Scan QR Code")
            $0.configuration?.image = UIImage(systemName: "qrcode.viewfinder")
        #endif
        $0.configuration?.imagePadding = 8
        $0.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
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
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        setupLayout()
    }

    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 8
            $0.setCustomSpacing(24, after: iconView)
        }

        view.addSubview(stack)
        view.addSubview(actionButton)
        view.addSubview(shadowOverlay)

        shadowOverlay.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        actionButton.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(32)
            $0.height.equalTo(50)
        }
    }

    @objc private func settingsTapped() {
        let settings = SettingsViewController()
        navigationController?.pushViewController(settings, animated: true)
    }

    @objc private func actionTapped() {
        #if targetEnvironment(macCatalyst)
            guard let string = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: string),
                  DeepLink(url: url) != nil
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
            sessionModel.startScan()
        #endif
    }
}
