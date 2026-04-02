import AlertController
import Combine
import SnapKit
import Then
import UIKit
import WebKit

class BrowserViewController: UIViewController {
    private let deepLink: DeepLink
    private let sessionModel: SessionUploadModel
    private let browser: BrowserCaptureModel
    private var cancellables = Set<AnyCancellable>()

    private lazy var sendButton = UIBarButtonItem(
        image: UIImage(systemName: "paperplane.fill"),
        style: .plain,
        target: self,
        action: #selector(sendTapped)
    )

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(deepLink: DeepLink, sessionModel: SessionUploadModel) {
        self.deepLink = deepLink
        self.sessionModel = sessionModel
        if let seed = sessionModel.seedSession {
            browser = BrowserCaptureModel(targetURL: deepLink.targetURL, deviceID: deepLink.deviceID, seedSession: seed)
            sessionModel.seedSession = nil
        } else {
            browser = BrowserCaptureModel(targetURL: deepLink.targetURL, deviceID: deepLink.deviceID)
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true

        view.addSubview(browser.webView)
        browser.webView.snp.makeConstraints { $0.edges.equalTo(view) }

        browser.webView.scrollView.refreshControl = UIRefreshControl().then {
            $0.addTarget(self, action: #selector(refresh), for: .valueChanged)
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
        navigationItem.rightBarButtonItem = sendButton
        title = String(localized: "Browser")

        bindModel()
    }

    // MARK: - Bindings

    private func bindModel() {
        browser.$pageTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pageTitle in
                self?.title = pageTitle.isEmpty ? String(localized: "Browser") : pageTitle
            }
            .store(in: &cancellables)

        browser.$isTransferring
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transferring in
                guard let self else { return }
                if transferring {
                    activityIndicator.startAnimating()
                    navigationItem.rightBarButtonItem = UIBarButtonItem(customView: activityIndicator)
                } else {
                    navigationItem.rightBarButtonItem = sendButton
                }
            }
            .store(in: &cancellables)

        browser.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap(\.self)
            .sink { [weak self] message in
                let alert = AlertViewController(
                    title: String(localized: "Navigation Error"),
                    message: message
                ) { context in
                    context.addAction(title: String(localized: "OK"), attribute: .dangerous) { context.dispose() }
                }
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)

        browser.$passkeyAlertPresented
            .receive(on: DispatchQueue.main)
            .filter { $0 }
            .sink { [weak self] _ in
                self?.browser.passkeyAlertPresented = false
                let alert = AlertViewController(
                    title: String(localized: "Passkey Not Supported"),
                    message: String(localized: "This website is requesting Passkey authentication, which is not supported in the in-app browser. Please use an alternative login method such as password or SMS verification.")
                ) { context in
                    context.addAction(title: String(localized: "OK")) { context.dispose() }
                }
                self?.present(alert, animated: true)
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func sendTapped() {
        let alert = AlertViewController(
            title: String(localized: "Send Session"),
            message: String(localized: "This will package and send the current session state to the requester. Please confirm you have completed login or the required actions.")
        ) { [weak self] context in
            context.addAction(title: String(localized: "Cancel")) {
                context.dispose()
            }
            context.addAction(title: String(localized: "Send"), attribute: .dangerous) {
                context.dispose {
                    self?.sendCurrentSession()
                }
            }
        }
        present(alert, animated: true)
    }

    private func sendCurrentSession() {
        Task {
            browser.isTransferring = true
            defer { browser.isTransferring = false }
            await sessionModel.captureAndUpload(from: browser, deepLink: deepLink)
        }
    }

    @objc private func backTapped() {
        sessionModel.resetToIdle()
    }

    @objc private func refresh() {
        browser.webView.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.browser.webView.scrollView.refreshControl?.endRefreshing()
        }
    }
}
