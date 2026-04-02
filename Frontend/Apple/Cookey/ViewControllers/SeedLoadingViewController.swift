import AlertController
import Combine
import SnapKit
import Then
import UIKit

final class SeedLoadingViewController: UIViewController {
    private let sessionModel: SessionUploadModel
    private let deepLink: DeepLink
    private var cancellables = Set<AnyCancellable>()
    private var hasPresentedPushExplanation = false

    private let activityIndicator = UIActivityIndicatorView(style: .large).then {
        $0.startAnimating()
    }

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 20, weight: .semibold)
        $0.textAlignment = .center
        $0.text = String(localized: "Loading session…")
    }

    private lazy var subtitleLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .footnote)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
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

        let stack = UIStackView(arrangedSubviews: [activityIndicator, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 12
        }

        view.addSubview(stack)
        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        bindModel()
        updateUI(for: sessionModel.loadingState)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPushExplanationIfNeeded()
    }

    private func bindModel() {
        sessionModel.$loadingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateUI(for: state)
            }
            .store(in: &cancellables)

        sessionModel.$shouldPresentPushExplanation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldPresent in
                guard shouldPresent else {
                    self?.hasPresentedPushExplanation = false
                    return
                }
                self?.presentPushExplanationIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func updateUI(for state: SessionUploadModel.LoadingState?) {
        let host = deepLink.serverURL.host() ?? deepLink.serverURL.absoluteString

        switch state {
        case let .checkingRequest(currentHost):
            titleLabel.text = String(localized: "Checking request…")
            subtitleLabel.text = String(localized: "Communicating with \(currentHost)…")
        case let .loadingSeed(currentHost):
            titleLabel.text = String(localized: "Loading session…")
            subtitleLabel.text = String(localized: "Downloading the latest session from \(currentHost)…")
        case nil:
            titleLabel.text = String(localized: "Loading session…")
            subtitleLabel.text = String(localized: "Communicating with \(host)…")
        }
    }

    private func presentPushExplanationIfNeeded() {
        guard sessionModel.shouldPresentPushExplanation, !hasPresentedPushExplanation, presentedViewController == nil else {
            return
        }

        hasPresentedPushExplanation = true
        let host = deepLink.serverURL.host(percentEncoded: false) ?? deepLink.serverURL.absoluteString
        let alert = AlertViewController(
            title: String(localized: "Enable APNs for Cookey?"),
            message: String(localized: "Cookey can use push notifications to refresh future login requests on this device for \(host). If you continue, iOS will show the system notification permission prompt and Cookey will wait for the APNs token callback before opening the website.")
        ) { [weak self] context in
            context.addAction(title: String(localized: "Not Now")) {
                context.dispose {
                    self?.sessionModel.respondToPushExplanation(allow: false)
                }
            }
            context.addAction(title: String(localized: "Continue"), attribute: .dangerous) {
                context.dispose {
                    self?.sessionModel.respondToPushExplanation(allow: true)
                }
            }
        }
        present(alert, animated: true)
    }
}
