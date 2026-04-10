import AlertController
import SnapKit
import Then
import UIKit

class WelcomePageViewController: UIViewController, UIScrollViewDelegate {
    var onComplete: (() -> Void)?

    private struct Page {
        let title: String.LocalizationValue
        let subtitle: String.LocalizationValue
        let icon: String?
        let color: UIColor?
        var command: String?
        var features: [(icon: String, color: UIColor, title: String.LocalizationValue, subtitle: String.LocalizationValue)]?
    }

    private let pages: [Page] = [
        Page(
            title: "Welcome to Cookey",
            subtitle: "Scan a QR code on your phone, log in on mobile, and your session lands encrypted in your terminal — ready for automation.",
            icon: nil,
            color: nil,
            features: [
                (icon: "lock.shield.fill", color: .systemGreen, title: "End-to-end Encrypted", subtitle: "Session data is encrypted on-device. The relay never sees plaintext."),
                (icon: "key.fill", color: .systemBlue, title: "Zero Registration", subtitle: "No accounts or enrollment. The CLI generates its own key pair on first run."),
                (icon: "terminal.fill", color: .systemPurple, title: "Built for Automation", subtitle: "Outputs Playwright-compatible JSON. Pipe into any browser automation tool."),
            ]
        ),
        Page(
            title: "1. Install the Skill",
            subtitle: "Simply paste and send this command to your AI agent (like Cursor or Claude) to install the skill.",
            icon: "puzzlepiece.extension.fill",
            color: .systemBlue,
            command: "npx skills add Lakr233/Cookey --skill website-login"
        ),
        Page(
            title: "2. Ask your Agent",
            subtitle: "Simply tell your AI to \"log in to a website\". It will generate a secure QR code in the terminal or chat.",
            icon: "apple.terminal.fill",
            color: .systemGreen
        ),
        Page(
            title: "3. Scan & Approve",
            subtitle: "Use this app to scan the code, log in normally, and securely deliver the session back to your AI.",
            icon: "qrcode.viewfinder",
            color: .accent
        ),
    ]

    private let scrollView = UIScrollView().then {
        $0.isPagingEnabled = true
        $0.showsHorizontalScrollIndicator = false
        $0.contentInsetAdjustmentBehavior = .never
    }

    private let stackView = UIStackView().then {
        $0.axis = .horizontal
        $0.distribution = .fillEqually
        $0.alignment = .fill
    }

    private let pageControl = UIPageControl().then {
        $0.currentPageIndicatorTintColor = .label
        $0.pageIndicatorTintColor = .tertiaryLabel
    }

    private lazy var actionButton = UIButton(configuration: .filled()).then {
        $0.configuration?.cornerStyle = .large
        $0.configuration?.baseBackgroundColor = .label
        $0.configuration?.baseForegroundColor = .systemBackground
        $0.configuration?.title = String(localized: "Next")
        $0.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
    }

    init(config _: Configuration = .default, onComplete: (() -> Void)? = nil) {
        // the original parameter `config` is ignored but kept for compatibility
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        modalTransitionStyle = .coverVertical
        isModalInPresentation = true
        preferredContentSize = .init(width: 520, height: 620)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        setupPages()

        pageControl.numberOfPages = pages.count
        pageControl.addTarget(self, action: #selector(pageChanged), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        view.addSubview(pageControl)
        view.addSubview(actionButton)

        scrollView.delegate = self

        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageControl.snp.top).offset(-16)
        }

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalToSuperview()
        }

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(actionButton.snp.top).offset(-24)
        }

        actionButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(24)
            make.height.equalTo(52)
        }
    }

    private func setupPages() {
        for page in pages {
            let pageView = UIView()

            let contentContainer = UIView()

            let titleLabel = UILabel().then {
                $0.text = String(localized: page.title)
                $0.font = .systemFont(ofSize: 28, weight: .bold)
                $0.textAlignment = .center
                $0.numberOfLines = 0
            }

            let subtitleLabel = UILabel().then {
                $0.text = String(localized: page.subtitle)
                $0.font = .preferredFont(forTextStyle: .body)
                $0.textColor = .secondaryLabel
                $0.textAlignment = .center
                $0.numberOfLines = 0
            }

            pageView.addSubview(contentContainer)
            contentContainer.addSubview(titleLabel)
            contentContainer.addSubview(subtitleLabel)

            if let icon = page.icon, let color = page.color {
                let iconContainer = UIView().then {
                    $0.backgroundColor = color.withAlphaComponent(0.15)
                    $0.layer.cornerRadius = 24
                    $0.layer.cornerCurve = .continuous
                }

                let iconView = UIImageView().then {
                    $0.image = UIImage(systemName: icon)
                    $0.tintColor = color
                    $0.contentMode = .scaleAspectFit
                    $0.preferredSymbolConfiguration = .init(pointSize: 64, weight: .light)
                }

                contentContainer.addSubview(iconContainer)
                iconContainer.addSubview(iconView)

                iconContainer.snp.makeConstraints { make in
                    make.top.centerX.equalToSuperview()
                    make.width.height.equalTo(120)
                }

                iconView.snp.makeConstraints { make in
                    make.center.equalToSuperview()
                    make.width.height.equalTo(64)
                }

                titleLabel.snp.makeConstraints { make in
                    make.top.equalTo(iconContainer.snp.bottom).offset(40)
                    make.leading.trailing.equalToSuperview()
                }
            } else {
                titleLabel.snp.makeConstraints { make in
                    make.top.equalToSuperview()
                    make.leading.trailing.equalToSuperview()
                }
            }

            subtitleLabel.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(16)
                make.leading.trailing.equalToSuperview()
                if page.command == nil, page.features == nil {
                    make.bottom.equalToSuperview()
                }
            }

            if let features = page.features {
                let featuresStack = UIStackView().then {
                    $0.axis = .vertical
                    $0.spacing = 28
                    $0.alignment = .fill
                }

                for feature in features {
                    let row = UIView()

                    let fIcon = UIImageView(image: UIImage(systemName: feature.icon)).then {
                        $0.tintColor = feature.color
                        $0.contentMode = .scaleAspectFit
                        $0.preferredSymbolConfiguration = .init(pointSize: 28, weight: .regular)
                    }

                    let textStack = UIStackView().then {
                        $0.axis = .vertical
                        $0.spacing = 4
                        $0.alignment = .leading
                    }

                    let fTitle = UILabel().then {
                        $0.text = String(localized: feature.title)
                        $0.font = .systemFont(ofSize: 17, weight: .semibold)
                    }

                    let fSub = UILabel().then {
                        $0.text = String(localized: feature.subtitle)
                        $0.font = .systemFont(ofSize: 15)
                        $0.textColor = .secondaryLabel
                        $0.numberOfLines = 0
                    }

                    textStack.addArrangedSubview(fTitle)
                    textStack.addArrangedSubview(fSub)

                    row.addSubview(fIcon)
                    row.addSubview(textStack)

                    fIcon.snp.makeConstraints { make in
                        make.leading.equalToSuperview()
                        make.top.equalToSuperview()
                        make.width.height.equalTo(36)
                    }

                    textStack.snp.makeConstraints { make in
                        make.leading.equalTo(fIcon.snp.trailing).offset(16)
                        make.trailing.equalToSuperview()
                        make.top.bottom.equalToSuperview()
                    }

                    featuresStack.addArrangedSubview(row)
                }

                contentContainer.addSubview(featuresStack)
                featuresStack.snp.makeConstraints { make in
                    make.top.equalTo(subtitleLabel.snp.bottom).offset(40)
                    make.leading.trailing.equalToSuperview()
                    make.bottom.equalToSuperview()
                }
            }

            if let command = page.command {
                let cmdButton = CommandButton(command: command)
                contentContainer.addSubview(cmdButton)

                cmdButton.snp.makeConstraints { make in
                    make.top.equalTo(subtitleLabel.snp.bottom).offset(32)
                    make.leading.trailing.equalToSuperview()
                    make.bottom.equalToSuperview()
                }
            }

            contentContainer.snp.makeConstraints { make in
                make.center.equalToSuperview()
                make.leading.trailing.equalToSuperview().inset(32)
            }

            stackView.addArrangedSubview(pageView)
            pageView.snp.makeConstraints { make in
                make.width.equalTo(view.snp.width)
            }
        }
    }

    @objc private func handleAction() {
        if pageControl.currentPage < pages.count - 1 {
            let nextIndex = pageControl.currentPage + 1
            let offset = CGPoint(x: view.bounds.width * CGFloat(nextIndex), y: 0)
            scrollView.setContentOffset(offset, animated: true)
        } else {
            onComplete?()
            dismiss(animated: true)
        }
    }

    @objc private func pageChanged() {
        let offset = CGPoint(x: view.bounds.width * CGFloat(pageControl.currentPage), y: 0)
        scrollView.setContentOffset(offset, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = round(scrollView.contentOffset.x / view.bounds.width)
        pageControl.currentPage = Int(page)

        let isLastPage = pageControl.currentPage == pages.count - 1
        UIView.animate(withDuration: 0.2) {
            self.actionButton.configuration?.title = isLastPage ? String(localized: "Get Started") : String(localized: "Next")
        }
    }
}

extension WelcomePageViewController {
    static func makePresentedController(
        config: Configuration = .default,
        onComplete: (() -> Void)? = nil
    ) -> UIViewController {
        let controller = WelcomePageViewController(config: config, onComplete: onComplete)

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.view.backgroundColor = .systemBackground
        navigationController.isModalInPresentation = true

        #if targetEnvironment(macCatalyst)
            return AlertBaseController(
                rootViewController: navigationController,
                preferredWidth: controller.preferredContentSize.width,
                preferredHeight: controller.preferredContentSize.height
            )
        #else
            navigationController.modalTransitionStyle = .coverVertical
            navigationController.modalPresentationStyle = .formSheet
            navigationController.preferredContentSize = controller.preferredContentSize
            return navigationController
        #endif
    }
}

private class CommandButton: UIControl {
    private let commandText: String

    private let copyIcon = UIImageView().then {
        $0.image = UIImage(systemName: "square.on.square")
        $0.tintColor = .secondaryLabel
        $0.contentMode = .scaleAspectFit
        $0.preferredSymbolConfiguration = .init(pointSize: 14, weight: .medium)
    }

    init(command: String) {
        commandText = command
        super.init(frame: .zero)

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.2).cgColor

        let promptLabel = UILabel().then {
            $0.text = "$"
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
            $0.textColor = .tertiaryLabel
        }

        let commandLabel = UILabel().then {
            $0.text = command
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            $0.textColor = .label
            $0.numberOfLines = 0
        }

        addSubview(promptLabel)
        addSubview(commandLabel)
        addSubview(copyIcon)

        promptLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(16)
        }

        commandLabel.snp.makeConstraints { make in
            make.leading.equalTo(promptLabel.snp.trailing).offset(12)
            make.trailing.equalTo(copyIcon.snp.leading).offset(-16)
            make.top.bottom.equalToSuperview().inset(16)
        }

        copyIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(18)
        }

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addTarget(self, action: #selector(copyCommandTapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.alpha = 0.7
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
            self.transform = .identity
        }
    }

    @objc private func copyCommandTapped() {
        UIPasteboard.general.string = commandText

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        UIView.transition(with: copyIcon, duration: 0.2, options: .transitionCrossDissolve, animations: {
            self.copyIcon.image = UIImage(systemName: "checkmark")
            self.copyIcon.tintColor = .systemGreen
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            UIView.transition(with: self.copyIcon, duration: 0.2, options: .transitionCrossDissolve, animations: {
                self.copyIcon.image = UIImage(systemName: "square.on.square")
                self.copyIcon.tintColor = .secondaryLabel
            })
        }
    }
}
