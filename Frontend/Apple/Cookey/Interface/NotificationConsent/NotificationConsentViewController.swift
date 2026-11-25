import Combine
import ConfigurableKit
import SnapKit
import Then
import UIKit

class NotificationConsentViewController: UIViewController {
    private let deepLink: DeepLink
    private let sessionModel: SessionUploadModel
    private var isSubmitting = false

    private let iconView = UIImageView().then {
        $0.image = UIImage(systemName: "bell.badge.fill")
        $0.tintColor = .label
        $0.contentMode = .scaleAspectFit
        $0.preferredSymbolConfiguration = .init(pointSize: 48, weight: .regular)
    }

    private let titleLabel = UILabel().then {
        $0.text = String(localized: "Enable login notifications?")
        $0.font = .systemFont(ofSize: 22, weight: .bold)
        $0.textAlignment = .center
    }

    private lazy var descriptionLabel = UILabel().then {
        let host = deepLink.serverURL.host(percentEncoded: false) ?? deepLink.serverURL.absoluteString
        $0.text = String(format: String(localized: "Cookey can send future login requests from %@ directly to this device. Your push token is only sent to the Cookey relay server you choose and is never shared with third parties."), host)
        $0.font = .preferredFont(forTextStyle: .footnote)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private lazy var enableButton = UIButton(configuration: .filled()).then {
        $0.configuration?.title = String(localized: "Enable Notifications")
        $0.configuration?.image = UIImage(systemName: "bell.badge.fill")
        $0.configuration?.imagePadding = 8
        $0.addTarget(self, action: #selector(enableTapped), for: .touchUpInside)
    }

    private lazy var declineButton = UIButton(configuration: .plain()).then {
        $0.configuration?.title = String(localized: "Not Now")
        $0.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)
    }

    init(deepLink: DeepLink, sessionModel: SessionUploadModel) {
        self.deepLink = deepLink
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
        navigationItem.hidesBackButton = true

        let stack = UIStackView(arrangedSubviews: [
            iconView, titleLabel, descriptionLabel,
        ]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 16
            $0.setCustomSpacing(8, after: titleLabel)
        }

        let foldRegion = FoldRegionView()
        view.addSubview(foldRegion)
        view.addSubview(stack)
        view.addSubview(enableButton)
        view.addSubview(declineButton)

        foldRegion.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        stack.snp.makeConstraints {
            $0.centerY.equalTo(foldRegion.contentRegion)
            $0.contentColumn(in: foldRegion.contentRegion)
        }

        enableButton.snp.makeConstraints {
            $0.contentColumn(in: foldRegion.controlRegion)
            $0.bottom.equalTo(declineButton.snp.top).offset(-8)
            $0.height.equalTo(50)
        }

        declineButton.snp.makeConstraints {
            $0.contentColumn(in: foldRegion.controlRegion)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(32)
        }
    }

    @objc private func enableTapped() {
        guard !isSubmitting else { return }
        isSubmitting = true
        enableButton.isEnabled = false
        enableButton.configuration?.showsActivityIndicator = true
        enableButton.configuration?.image = nil
        ConfigurableKit.set(value: true, forKey: AppSettings.allowRefreshKey)
        Task {
            let completed = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await self.sessionModel.respondToPushExplanation(allow: true)
                    await self.sessionModel.resetToIdle()
                    return true
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(10))
                    return false
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }
            if !completed {
                isSubmitting = false
                enableButton.isEnabled = true
                enableButton.configuration?.showsActivityIndicator = false
                enableButton.configuration?.image = UIImage(systemName: "bell.badge.fill")
                sessionModel.resetToIdle()
            }
        }
    }

    @objc private func declineTapped() {
        sessionModel.respondToPushExplanation(allow: false)
        sessionModel.resetToIdle()
    }
}
