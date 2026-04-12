import AlertController
import SnapKit
import Then
import UIKit

class WelcomePageViewController: UIViewController, UIScrollViewDelegate {
    var onComplete: (() -> Void)?

    private static let agentMarkdown = """
    # Cookey

    Use Cookey to let a human complete login on their mobile device and return the \
    browser session to your terminal.

    Fetch the full instructions from https://cookey.sh/llms.txt.
    """

    private struct Page {
        let title: String.LocalizationValue
        let subtitle: String.LocalizationValue
    }

    private let pages: [Page] = [
        Page(
            title: "Install the Skill",
            subtitle: "Copy the instructions and send to your AI agent. It will handle the rest."
        ),
        Page(
            title: "Ask your Agent",
            subtitle: "Tell your AI to log in to a website. It will generate a secure QR code in the terminal or chat. If scanning isn't possible, ask it for a link instead."
        ),
        Page(
            title: "Scan & Approve",
            subtitle: "Scan the QR code with this app and complete login. Your session will be securely delivered back to your AI."
        ),
    ]

    private let welcomePageIndex = 0
    private let agentPageIndex = 2

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
        let titleAttr = AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        $0.configuration?.attributedTitle = AttributedString(String(localized: "Next"), attributes: titleAttr)
        $0.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
    }

    private weak var agentQRBlurView: UIVisualEffectView?
    private var agentChatViews: [UIView] = []
    private var hasRevealedAgent = false
    private var isTransitioning = false

    init(onComplete: (() -> Void)? = nil) {
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

        pageControl.numberOfPages = pages.count + 1 // welcome + step pages
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
        // Page 0: Welcome
        let welcomePage = makeWelcomePage()
        stackView.addArrangedSubview(welcomePage)
        welcomePage.snp.makeConstraints { make in
            make.width.equalTo(view.snp.width)
        }

        // Pages 1-3: Steps
        let accessories: [UIView?] = [
            makeInstallAccessory(),
            makeAgentAccessory(),
            makeScanAccessory(),
        ]

        for (i, page) in pages.enumerated() {
            let stepView = SetupStepView(
                title: String(localized: page.title),
                subtitle: String(localized: page.subtitle),
                accessory: accessories[i]
            )
            stackView.addArrangedSubview(stepView)
            stepView.snp.makeConstraints { make in
                make.width.equalTo(view.snp.width)
            }
        }
    }

    // MARK: - Page 0: Welcome

    private func makeWelcomePage() -> UIView {
        let pageView = UIView()

        let iconView = UIImageView().then {
            $0.image = UIImage(named: "Avatar")
            $0.contentMode = .scaleAspectFit
            $0.layer.cornerRadius = 28
            $0.layer.cornerCurve = .continuous
            $0.clipsToBounds = true
        }

        let titleLabel = UILabel().then {
            $0.text = String(localized: "Welcome to Cookey")
            $0.font = .systemFont(ofSize: 32, weight: .bold)
            $0.textColor = .label
            $0.textAlignment = .center
            $0.numberOfLines = 0
        }

        let subtitleLabel = UILabel().then {
            $0.text = String(localized: "Help your AI log in. We keep your data safe.")
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .secondaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 0
        }

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 16
            $0.setCustomSpacing(24, after: iconView)
            $0.setCustomSpacing(12, after: titleLabel)
        }

        pageView.addSubview(stack)

        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(120)
        }

        stack.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(-40)
            make.leading.trailing.equalToSuperview().inset(32)
        }

        return pageView
    }

    // MARK: - Page 1: Install — Receipt + Copy button

    private func makeInstallAccessory() -> UIView {
        let stack = UIStackView().then {
            $0.axis = .vertical
            $0.spacing = 16
            $0.alignment = .fill
        }

        let receipt = ReceiptView()
        stack.addArrangedSubview(receipt)

        let copyButton = makeCopyButton()
        stack.addArrangedSubview(copyButton)
        copyButton.snp.makeConstraints { make in
            make.height.equalTo(52)
        }

        return stack
    }

    private func makeCopyButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = .label
        config.baseForegroundColor = .systemBackground
        let titleAttr = AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        config.attributedTitle = AttributedString(String(localized: "Copy for Agents"), attributes: titleAttr)
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(copyForAgentsTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func copyForAgentsTapped(_ sender: UIButton) {
        UIPasteboard.general.string = Self.agentMarkdown

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let boldAttr = AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        sender.configuration?.attributedTitle = AttributedString(String(localized: "Copied"), attributes: boldAttr)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.configuration?.attributedTitle = AttributedString(String(localized: "Copy for Agents"), attributes: boldAttr)
        }
    }

    // MARK: - Page 2: Agent — Chat + QR reveal

    private func makeAgentAccessory() -> UIView {
        let stack = UIStackView().then {
            $0.axis = .vertical
            $0.spacing = 16
            $0.alignment = .fill
        }

        // User bubble (right-aligned)
        let userRow = UIView()
        let userBubble = UIView().then {
            $0.backgroundColor = .accent
            $0.layer.cornerRadius = 18
            $0.layer.cornerCurve = .continuous
            $0.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        }
        let userLabel = UILabel().then {
            $0.text = String(localized: "Help me log in to example.com")
            $0.font = .systemFont(ofSize: 16)
            $0.textColor = .white
            $0.numberOfLines = 0
        }
        userBubble.addSubview(userLabel)
        userRow.addSubview(userBubble)
        userLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        }
        userBubble.snp.makeConstraints { make in
            make.top.trailing.bottom.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(48)
        }
        stack.addArrangedSubview(userRow)

        // Agent bubble (left-aligned)
        let agentRow = UIView()
        let agentBubble = UIView().then {
            $0.backgroundColor = .secondarySystemFill
            $0.layer.cornerRadius = 18
            $0.layer.cornerCurve = .continuous
            $0.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        let agentLabel = UILabel().then {
            $0.text = String(localized: "Sure, here's your QR code 👇")
            $0.font = .systemFont(ofSize: 16)
            $0.textColor = .label
            $0.numberOfLines = 0
        }
        agentBubble.addSubview(agentLabel)
        agentRow.addSubview(agentBubble)
        agentLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        }
        agentBubble.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-48)
        }
        stack.addArrangedSubview(agentRow)

        // QR code (left-aligned square, with blur reveal)
        let qrRow = UIView()
        let qrContainer = UIView().then {
            $0.backgroundColor = .tertiarySystemFill
            $0.layer.cornerRadius = 16
            $0.layer.cornerCurve = .continuous
            $0.clipsToBounds = true
        }

        let qrImage = UIImageView().then {
            $0.image = UIImage(systemName: "qrcode")
            $0.tintColor = .label
            $0.contentMode = .scaleAspectFit
            $0.preferredSymbolConfiguration = .init(pointSize: 48, weight: .light)
        }

        let blurOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial)).then {
            $0.clipsToBounds = true
            $0.layer.cornerRadius = 16
        }
        agentQRBlurView = blurOverlay

        qrContainer.addSubview(qrImage)
        qrContainer.addSubview(blurOverlay)
        qrRow.addSubview(qrContainer)

        qrImage.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        blurOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        qrContainer.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.height.equalTo(100)
        }
        stack.addArrangedSubview(qrRow)

        // Agent bubble: host key with emoji
        let keyRow = UIView()
        let keyBubble = UIView().then {
            $0.backgroundColor = .secondarySystemFill
            $0.layer.cornerRadius = 18
            $0.layer.cornerCurve = .continuous
            $0.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        let keyLabel = UILabel().then {
            $0.text = String(localized: "Host key: 🍪🔑🛡️✨")
            $0.font = .systemFont(ofSize: 16)
            $0.textColor = .label
            $0.numberOfLines = 0
        }
        keyBubble.addSubview(keyLabel)
        keyRow.addSubview(keyBubble)
        keyLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        }
        keyBubble.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-48)
        }
        stack.addArrangedSubview(keyRow)

        // Store references and set initial hidden state
        agentChatViews = [userRow, agentRow, qrRow, keyRow]
        for v in agentChatViews {
            v.alpha = 0
            v.transform = CGAffineTransform(translationX: 0, y: 12)
        }

        return stack
    }

    private func revealAgentChat() {
        guard !hasRevealedAgent else { return }
        hasRevealedAgent = true

        for (i, chatView) in agentChatViews.enumerated() {
            UIView.animate(
                withDuration: 0.45,
                delay: Double(i) * 0.2,
                options: .curveEaseOut
            ) {
                chatView.alpha = 1
                chatView.transform = .identity
            }
        }

        // QR blur reveal after bubbles finish
        UIView.animate(
            withDuration: 0.8,
            delay: Double(agentChatViews.count) * 0.2,
            options: .curveEaseOut
        ) {
            self.agentQRBlurView?.effect = nil
        }
    }

    // MARK: - Page 3: Scan — QR animation + completion chat

    private func makeScanAccessory() -> UIView {
        let stack = UIStackView().then {
            $0.axis = .vertical
            $0.spacing = 16
            $0.alignment = .fill
        }

        let qrView = QRScanAnimationView()
        qrView.snp.makeConstraints { make in
            make.height.equalTo(160)
        }
        stack.addArrangedSubview(qrView)

        // Link fallback note
        let linkNote = UILabel().then {
            $0.text = String(localized: "If you can't scan, open the link your AI provided — it will redirect to this app automatically.")
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .secondaryLabel
            $0.numberOfLines = 0
        }
        stack.addArrangedSubview(linkNote)

        // Security note
        let securityNote = UILabel().then {
            $0.text = String(localized: "To verify security, ask your AI to visit our website and review our source code.")
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .systemRed
            $0.numberOfLines = 0
        }
        stack.addArrangedSubview(securityNote)

        // User bubble: "I've finished logging in"
        let userRow = UIView()
        let userBubble = UIView().then {
            $0.backgroundColor = .accent
            $0.layer.cornerRadius = 18
            $0.layer.cornerCurve = .continuous
            $0.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
        }
        let userLabel = UILabel().then {
            $0.text = String(localized: "I've finished logging in ✅")
            $0.font = .systemFont(ofSize: 16)
            $0.textColor = .white
            $0.numberOfLines = 0
        }
        userBubble.addSubview(userLabel)
        userRow.addSubview(userBubble)
        userLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        }
        userBubble.snp.makeConstraints { make in
            make.top.trailing.bottom.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(48)
        }
        stack.addArrangedSubview(userRow)

        // Agent bubble: response
        let agentRow = UIView()
        let agentBubble = UIView().then {
            $0.backgroundColor = .secondarySystemFill
            $0.layer.cornerRadius = 18
            $0.layer.cornerCurve = .continuous
            $0.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        let agentLabel = UILabel().then {
            $0.text = String(localized: "Got it, I can see your homepage now. What would you like me to do?")
            $0.font = .systemFont(ofSize: 16)
            $0.textColor = .label
            $0.numberOfLines = 0
        }
        agentBubble.addSubview(agentLabel)
        agentRow.addSubview(agentBubble)
        agentLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14))
        }
        agentBubble.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview().offset(-48)
        }
        stack.addArrangedSubview(agentRow)

        return stack
    }

    // MARK: - Actions

    @objc private func handleAction() {
        guard !isTransitioning else { return }
        let totalPages = pages.count + 1
        if pageControl.currentPage < totalPages - 1 {
            isTransitioning = true
            let nextIndex = pageControl.currentPage + 1
            let target = CGPoint(x: view.bounds.width * CGFloat(nextIndex), y: 0)
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.3,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                self.scrollView.contentOffset = target
            } completion: { _ in
                self.isTransitioning = false
            }
        } else {
            onComplete?()
            dismiss(animated: true)
        }
    }

    @objc private func pageChanged() {
        guard !isTransitioning else { return }
        isTransitioning = true
        let target = CGPoint(x: view.bounds.width * CGFloat(pageControl.currentPage), y: 0)
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.3,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.scrollView.contentOffset = target
        } completion: { _ in
            self.isTransitioning = false
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.scrollView else { return }
        let page = round(scrollView.contentOffset.x / view.bounds.width)
        pageControl.currentPage = Int(page)

        let totalPages = pages.count + 1
        let isLastPage = pageControl.currentPage == totalPages - 1
        let title = isLastPage ? String(localized: "Get Started") : String(localized: "Next")
        let boldAttr = AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        UIView.animate(withDuration: 0.2) {
            self.actionButton.configuration?.attributedTitle = AttributedString(title, attributes: boldAttr)
        }

        if pageControl.currentPage == agentPageIndex {
            revealAgentChat()
        }
    }
}

// MARK: - Presentation

extension WelcomePageViewController {
    static func makePresentedController(
        onComplete: (() -> Void)? = nil
    ) -> UIViewController {
        let controller = WelcomePageViewController(onComplete: onComplete)

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

// MARK: - Receipt View

private class ReceiptView: UIView {
    private let titleLabel = UILabel().then {
        $0.text = "Cookey"
        $0.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        $0.textColor = UIColor(white: 0.1, alpha: 1)
    }

    private let bodyLabel = UILabel().then {
        $0.text = """
        Use Cookey to let a human complete \
        login on their mobile device and \
        return the browser session to your \
        terminal.

        Fetch the full instructions from \
        https://cookey.sh/llms.txt.
        """
        $0.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        $0.textColor = UIColor(white: 0.45, alpha: 1)
        $0.numberOfLines = 0
    }

    private let footerLabel = UILabel().then {
        $0.text = "INSTRUCTION"
        $0.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        $0.textColor = UIColor(white: 0.55, alpha: 1)
        $0.textAlignment = .center
    }

    private let decoLabel = UILabel().then {
        $0.text = "EN"
        $0.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        $0.textColor = UIColor(white: 0.65, alpha: 1)
    }

    private let tearLineLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel]).then {
            $0.axis = .vertical
            $0.spacing = 8
            $0.alignment = .leading
        }

        addSubview(contentStack)
        addSubview(footerLabel)
        addSubview(decoLabel)
        layer.addSublayer(tearLineLayer)

        contentStack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }

        footerLabel.snp.makeConstraints { make in
            make.top.equalTo(contentStack.snp.bottom).offset(28)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(14)
        }

        decoLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTearLine()
        updateMask()
    }

    private func updateTearLine() {
        let tearY = footerLabel.frame.minY - 8
        let notchR: CGFloat = 6
        let dashPath = UIBezierPath()
        dashPath.move(to: CGPoint(x: notchR + 4, y: tearY))
        dashPath.addLine(to: CGPoint(x: bounds.width - notchR - 4, y: tearY))

        tearLineLayer.path = dashPath.cgPath
        tearLineLayer.strokeColor = UIColor(white: 0.82, alpha: 1).cgColor
        tearLineLayer.lineWidth = 1
        tearLineLayer.lineDashPattern = [4, 3]
        tearLineLayer.fillColor = nil
        tearLineLayer.frame = bounds
    }

    private func updateMask() {
        let tearY = footerLabel.frame.minY - 8
        let notchR: CGFloat = 6

        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 12)
        path.usesEvenOddFillRule = true
        path.append(UIBezierPath(
            arcCenter: CGPoint(x: 0, y: tearY),
            radius: notchR, startAngle: 0, endAngle: .pi * 2, clockwise: true
        ))
        path.append(UIBezierPath(
            arcCenter: CGPoint(x: bounds.width, y: tearY),
            radius: notchR, startAngle: 0, endAngle: .pi * 2, clockwise: true
        ))

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        layer.mask = mask
    }
}

// MARK: - QR Scan Animation View

private class QRScanAnimationView: UIView {
    private let bracketLayer = CAShapeLayer()
    private let qrDotsLayer = CAShapeLayer()
    private let scanLineLayer = CAShapeLayer()
    private let qrSize: CGFloat = 160

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(bracketLayer)
        layer.addSublayer(qrDotsLayer)
        layer.addSublayer(scanLineLayer)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: QRScanAnimationView, _: UITraitCollection) in
            self.drawQR()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        drawQR()
        animateScanLine()
    }

    private func drawQR() {
        let viewSize = bounds.size
        guard viewSize.width > 0 else { return }

        let ox = (viewSize.width - qrSize) / 2
        let r = CGRect(x: ox, y: 0, width: qrSize, height: qrSize)

        let bracketLen: CGFloat = 24
        let inset: CGFloat = 8

        // Corner brackets
        let bp = UIBezierPath()
        bp.move(to: CGPoint(x: r.minX + inset, y: r.minY + inset + bracketLen))
        bp.addLine(to: CGPoint(x: r.minX + inset, y: r.minY + inset))
        bp.addLine(to: CGPoint(x: r.minX + inset + bracketLen, y: r.minY + inset))

        bp.move(to: CGPoint(x: r.maxX - inset - bracketLen, y: r.minY + inset))
        bp.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY + inset))
        bp.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY + inset + bracketLen))

        bp.move(to: CGPoint(x: r.minX + inset, y: r.maxY - inset - bracketLen))
        bp.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY - inset))
        bp.addLine(to: CGPoint(x: r.minX + inset + bracketLen, y: r.maxY - inset))

        bp.move(to: CGPoint(x: r.maxX - inset - bracketLen, y: r.maxY - inset))
        bp.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY - inset))
        bp.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY - inset - bracketLen))

        bracketLayer.path = bp.cgPath
        bracketLayer.strokeColor = UIColor.label.withAlphaComponent(0.5).cgColor
        bracketLayer.fillColor = nil
        bracketLayer.lineWidth = 2
        bracketLayer.lineCap = .round
        bracketLayer.lineJoin = .round
        bracketLayer.frame = bounds

        // QR content
        let dp = UIBezierPath()
        let gridInset: CGFloat = 28
        let area = CGRect(
            x: r.minX + gridInset, y: r.minY + gridInset,
            width: qrSize - gridInset * 2, height: qrSize - gridInset * 2
        )
        let finderSize: CGFloat = 28
        let dotSize: CGFloat = 5

        // Three finder patterns
        func addFinder(at origin: CGPoint) {
            let inner = finderSize * 0.45
            dp.append(UIBezierPath(roundedRect: CGRect(x: origin.x, y: origin.y, width: finderSize, height: finderSize), cornerRadius: 2))
            dp.append(UIBezierPath(roundedRect: CGRect(
                x: origin.x + (finderSize - inner) / 2,
                y: origin.y + (finderSize - inner) / 2,
                width: inner, height: inner
            ), cornerRadius: 1))
        }

        addFinder(at: CGPoint(x: area.minX, y: area.minY))
        addFinder(at: CGPoint(x: area.maxX - finderSize, y: area.minY))
        addFinder(at: CGPoint(x: area.minX, y: area.maxY - finderSize))

        let dataDots: [(CGFloat, CGFloat)] = [
            (0.42, 0.10), (0.55, 0.10), (0.42, 0.22),
            (0.10, 0.42), (0.22, 0.42), (0.42, 0.42),
            (0.55, 0.42), (0.70, 0.42), (0.85, 0.42),
            (0.55, 0.55), (0.70, 0.70), (0.85, 0.70),
            (0.70, 0.85), (0.85, 0.85),
        ]

        for (px, py) in dataDots {
            dp.append(UIBezierPath(
                roundedRect: CGRect(
                    x: area.minX + area.width * px,
                    y: area.minY + area.height * py,
                    width: dotSize, height: dotSize
                ),
                cornerRadius: 1
            ))
        }

        qrDotsLayer.path = dp.cgPath
        qrDotsLayer.fillColor = UIColor.label.withAlphaComponent(0.25).cgColor
        qrDotsLayer.frame = bounds

        // Scan line
        let lp = UIBezierPath()
        lp.move(to: CGPoint(x: r.minX + inset + 4, y: r.midY))
        lp.addLine(to: CGPoint(x: r.maxX - inset - 4, y: r.midY))

        scanLineLayer.path = lp.cgPath
        scanLineLayer.strokeColor = UIColor.accent.withAlphaComponent(0.6).cgColor
        scanLineLayer.lineWidth = 1.5
        scanLineLayer.lineCap = .round
        scanLineLayer.frame = bounds
    }

    private func animateScanLine() {
        scanLineLayer.removeAllAnimations()

        let travel = qrSize - 24
        let anim = CABasicAnimation(keyPath: "transform.translation.y")
        anim.fromValue = -travel / 2
        anim.toValue = travel / 2
        anim.duration = 2.5
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLineLayer.add(anim, forKey: "scan")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.2
        fade.toValue = 0.8
        fade.duration = 2.5
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLineLayer.add(fade, forKey: "fade")
    }
}
