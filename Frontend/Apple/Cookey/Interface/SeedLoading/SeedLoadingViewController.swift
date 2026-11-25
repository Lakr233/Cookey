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
    private var hasPresentedKeyVerification = false
    private var isPresentingModal = false

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
        Logger.ui.infoFile("SeedLoadingViewController loaded for rid \(deepLink.rid)")
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true

        let stack = UIStackView(arrangedSubviews: [activityIndicator, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 12
        }

        let foldRegion = FoldRegionView()
        view.addSubview(foldRegion)
        view.addSubview(stack)
        foldRegion.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        stack.snp.makeConstraints {
            $0.centerY.equalTo(foldRegion.contentRegion)
            $0.contentColumn(in: foldRegion.contentRegion)
        }

        bindModel()
        updateUI(for: sessionModel.loadingState)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPendingModalIfNeeded()
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
                self?.presentPendingModalIfNeeded()
            }
            .store(in: &cancellables)

        sessionModel.$shouldPresentKeyVerification
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldPresent in
                guard shouldPresent else {
                    self?.hasPresentedKeyVerification = false
                    return
                }
                self?.presentPendingModalIfNeeded()
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

    /// Single entry point for modal presentation. Checks in priority order
    /// (key verification before push explanation) and waits for each modal
    /// to dismiss before presenting the next.
    private func presentPendingModalIfNeeded() {
        guard !isPresentingModal, presentedViewController == nil else { return }

        if sessionModel.shouldPresentKeyVerification,
           !hasPresentedKeyVerification,
           let state = sessionModel.keyVerificationState
        {
            isPresentingModal = true
            hasPresentedKeyVerification = true
            Logger.ui.infoFile("Presenting key verification for rid \(deepLink.rid)")
            let vc = KeyVerificationViewController(verificationState: state) { [weak self] trusted in
                self?.sessionModel.respondToKeyVerification(trust: trusted)
                self?.isPresentingModal = false
                self?.presentPendingModalIfNeeded()
            }
            present(vc, animated: true)
            return
        }

        if sessionModel.shouldPresentPushExplanation, !hasPresentedPushExplanation {
            isPresentingModal = true
            hasPresentedPushExplanation = true
            Logger.push.infoFile("Presenting push explanation for rid \(deepLink.rid)")
            let host = deepLink.serverURL.host(percentEncoded: false) ?? deepLink.serverURL.absoluteString
            let alert = AlertViewController(
                title: String(localized: "Enable Push Notifications for Cookey?"),
                message: String(localized: "If you enable push notifications, future login or session refresh requests for \(host) can be sent directly to this device — no need to scan a QR code or enter a pairing code again.\n\nThis is optional — Cookey works perfectly without notifications. You can change this later in Settings."),
            ) { [weak self] context in
                context.addAction(title: String(localized: "Not Now")) {
                    context.dispose {
                        Logger.push.infoFile("User declined push explanation for rid \(self?.deepLink.rid ?? "<unknown>")")
                        self?.sessionModel.respondToPushExplanation(allow: false)
                        self?.isPresentingModal = false
                        self?.presentPendingModalIfNeeded()
                    }
                }
                context.addAction(title: String(localized: "Continue"), attribute: .dangerous) {
                    context.dispose {
                        Logger.push.infoFile("User accepted push explanation for rid \(self?.deepLink.rid ?? "<unknown>")")
                        self?.sessionModel.respondToPushExplanation(allow: true)
                        self?.isPresentingModal = false
                        self?.presentPendingModalIfNeeded()
                    }
                }
            }
            present(alert, animated: true)
            return
        }
    }
}
