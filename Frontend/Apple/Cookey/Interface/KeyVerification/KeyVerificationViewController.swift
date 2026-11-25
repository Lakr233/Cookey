import SnapKit
import Then
import UIKit

final class KeyVerificationViewController: UIViewController {
    private let verificationState: KeyVerificationState
    private let onResponse: (Bool) -> Void
    private var separatorHeightConstraints: [Constraint] = []

    // MARK: - Icon

    private let iconView = UIImageView().then {
        $0.contentMode = .scaleAspectFit
        $0.tintColor = .label
        $0.preferredSymbolConfiguration = .init(pointSize: 56, weight: .ultraLight)
    }

    // MARK: - Text

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 24, weight: .bold)
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let messageLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .subheadline)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    // MARK: - Fingerprint card

    private let fingerprintCard = UIView().then {
        $0.backgroundColor = .secondarySystemBackground
        $0.layer.cornerRadius = 16
    }

    private let hexLabel = UILabel().then {
        $0.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        $0.textAlignment = .center
        $0.textColor = .label
    }

    private let cardSeparator = UIView().then {
        $0.backgroundColor = .separator
    }

    private let emojiRow1 = UILabel().then {
        $0.font = .systemFont(ofSize: 32)
        $0.textAlignment = .center
    }

    private let emojiRow2 = UILabel().then {
        $0.font = .systemFont(ofSize: 32)
        $0.textAlignment = .center
    }

    // MARK: - Key changed: old fingerprint

    private let oldFingerprintCard = UIView().then {
        $0.backgroundColor = .secondarySystemBackground
        $0.layer.cornerRadius = 16
    }

    private let oldHexLabel = UILabel().then {
        $0.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        $0.textAlignment = .center
        $0.textColor = .secondaryLabel
    }

    private let oldCardSeparator = UIView().then {
        $0.backgroundColor = .separator
    }

    private let oldEmojiRow1 = UILabel().then {
        $0.font = .systemFont(ofSize: 32)
        $0.textAlignment = .center
    }

    private let oldEmojiRow2 = UILabel().then {
        $0.font = .systemFont(ofSize: 32)
        $0.textAlignment = .center
    }

    private let oldFingerprintHeader = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .tertiaryLabel
        $0.textAlignment = .center
        $0.text = String(localized: "Previous fingerprint")
    }

    private let newFingerprintHeader = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .caption1)
        $0.textColor = .tertiaryLabel
        $0.textAlignment = .center
        $0.text = String(localized: "New fingerprint")
    }

    // MARK: - Buttons

    private lazy var trustButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(trustTapped), for: .touchUpInside)
        return button
    }()

    private lazy var rejectButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .systemRed
        config.buttonSize = .large
        let button = UIButton(configuration: config)
        button.setTitle(String(localized: "Reject"), for: .normal)
        button.addTarget(self, action: #selector(rejectTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Content scroll view

    // The content scrolls when it is taller than the space above the
    // buttons, for example on a short display, so the buttons stay visible.
    private let contentScrollView = UIScrollView().then {
        $0.contentInsetAdjustmentBehavior = .never
        $0.alwaysBounceVertical = false
    }

    // MARK: - Init

    init(verificationState: KeyVerificationState, onResponse: @escaping (Bool) -> Void) {
        self.verificationState = verificationState
        self.onResponse = onResponse
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureForState()
        layoutUI()
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: Self, _) in
            self.updateSeparatorHeights()
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateSeparatorHeights()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Show that more of the fingerprints is below when it does not fit.
        contentScrollView.flashScrollIndicators()
    }

    private func updateSeparatorHeights() {
        let height = 1.0 / max(traitCollection.displayScale, 1)
        for constraint in separatorHeightConstraints {
            constraint.update(offset: height)
        }
    }

    // MARK: - Configure

    private struct FingerprintParts {
        let hex: String
        let emojis: [String]

        var emojiLine1: String {
            emojis.prefix(3).joined(separator: "  ")
        }

        var emojiLine2: String {
            emojis.dropFirst(3).prefix(3).joined(separator: "  ")
        }
    }

    private func parseFingerprintParts(_ fingerprint: String) -> FingerprintParts {
        let components = fingerprint.components(separatedBy: "  ")
        let hex = components.first ?? fingerprint
        let emojis: [String] = if components.count > 1 {
            components.dropFirst().joined(separator: "  ")
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
        } else {
            []
        }
        return FingerprintParts(hex: hex, emojis: emojis)
    }

    private func configureForState() {
        switch verificationState {
        case let .firstTime(fingerprint):
            let parts = parseFingerprintParts(fingerprint)
            iconView.image = UIImage(systemName: "desktopcomputer")
            titleLabel.text = String(localized: "New Key")
            messageLabel.text = String(localized: "First connection from this computer. Verify the fingerprint below matches what your terminal shows. If they don't match, reject the connection — it may be intercepted by a third party.")
            hexLabel.text = parts.hex
            emojiRow1.text = parts.emojiLine1
            emojiRow2.text = parts.emojiLine2
            trustButton.setTitle(String(localized: "Trust"), for: .normal)

        case let .keyChanged(oldFingerprint, newFingerprint):
            let oldParts = parseFingerprintParts(oldFingerprint)
            let newParts = parseFingerprintParts(newFingerprint)
            iconView.image = UIImage(systemName: "exclamationmark.shield")
            iconView.tintColor = .systemOrange
            titleLabel.text = String(localized: "Security Warning")
            messageLabel.text = String(localized: "The identity of this computer has changed since you last connected. This could indicate a security issue, or the command-line tool may have been reinstalled.")
            hexLabel.text = newParts.hex
            emojiRow1.text = newParts.emojiLine1
            emojiRow2.text = newParts.emojiLine2
            oldHexLabel.text = oldParts.hex
            oldEmojiRow1.text = oldParts.emojiLine1
            oldEmojiRow2.text = oldParts.emojiLine2
            trustButton.setTitle(String(localized: "Trust New Key"), for: .normal)

        case let .knownKeyNewDevice(fingerprint):
            let parts = parseFingerprintParts(fingerprint)
            iconView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            titleLabel.text = String(localized: "Known Key, New Device")
            messageLabel.text = String(localized: "This key was previously trusted under a different device identifier. This may indicate the command-line tool was migrated or reinstalled.")
            hexLabel.text = parts.hex
            emojiRow1.text = parts.emojiLine1
            emojiRow2.text = parts.emojiLine2
            trustButton.setTitle(String(localized: "Trust"), for: .normal)

        case .trusted:
            break
        }
    }

    // MARK: - Layout

    private func buildFingerprintCardContent(in card: UIView, hex: UILabel, separator: UIView, emoji1: UILabel, emoji2: UILabel) {
        let stack = UIStackView(arrangedSubviews: [hex, separator, emoji1, emoji2]).then {
            $0.axis = .vertical
            $0.spacing = 16
            $0.alignment = .center
        }
        card.addSubview(stack)
        stack.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20))
        }
        separator.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            separatorHeightConstraints.append($0.height.equalTo(1.0 / max(traitCollection.displayScale, 1)).constraint)
        }
    }

    private func layoutUI() {
        let isKeyChanged: Bool = {
            if case .keyChanged = verificationState { return true }
            return false
        }()

        // Content area
        var contentViews: [UIView] = [iconView, titleLabel, messageLabel]

        // Fingerprint card(s)
        buildFingerprintCardContent(in: fingerprintCard, hex: hexLabel, separator: cardSeparator, emoji1: emojiRow1, emoji2: emojiRow2)

        if isKeyChanged {
            buildFingerprintCardContent(in: oldFingerprintCard, hex: oldHexLabel, separator: oldCardSeparator, emoji1: oldEmojiRow1, emoji2: oldEmojiRow2)

            let oldSection = UIStackView(arrangedSubviews: [oldFingerprintHeader, oldFingerprintCard]).then {
                $0.axis = .vertical
                $0.spacing = 6
                $0.alignment = .fill
            }
            let newSection = UIStackView(arrangedSubviews: [newFingerprintHeader, fingerprintCard]).then {
                $0.axis = .vertical
                $0.spacing = 6
                $0.alignment = .fill
            }
            contentViews.append(oldSection)
            contentViews.append(newSection)
        } else {
            contentViews.append(fingerprintCard)
        }

        let contentStack = UIStackView(arrangedSubviews: contentViews).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 16
        }
        contentStack.setCustomSpacing(24, after: iconView)
        contentStack.setCustomSpacing(8, after: titleLabel)

        // Button area pinned to bottom
        let buttonStack = UIStackView(arrangedSubviews: [trustButton, rejectButton]).then {
            $0.axis = .vertical
            $0.spacing = 4
            $0.alignment = .fill
        }

        view.addSubview(contentScrollView)
        contentScrollView.addSubview(contentStack)
        view.addSubview(buttonStack)

        contentScrollView.snp.makeConstraints {
            $0.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            $0.bottom.equalTo(buttonStack.snp.top).offset(-24)
        }

        contentScrollView.contentLayoutGuide.snp.makeConstraints {
            $0.width.equalTo(contentScrollView.frameLayoutGuide)
            $0.height.greaterThanOrEqualTo(contentScrollView.frameLayoutGuide)
            $0.height.equalTo(contentScrollView.frameLayoutGuide).priority(.low)
        }

        contentStack.snp.makeConstraints {
            $0.top.greaterThanOrEqualTo(contentScrollView.contentLayoutGuide).offset(32)
            $0.bottom.lessThanOrEqualTo(contentScrollView.contentLayoutGuide)
            $0.centerY.equalTo(view).offset(-40).priority(.medium)
            $0.contentColumn(in: view.safeAreaLayoutGuide)
        }

        buttonStack.snp.makeConstraints {
            $0.contentColumn(in: view.safeAreaLayoutGuide)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).offset(-16)
        }

        iconView.snp.makeConstraints { $0.height.equalTo(56) }
        fingerprintCard.snp.makeConstraints { $0.leading.trailing.equalToSuperview() }

        if isKeyChanged {
            oldFingerprintCard.snp.makeConstraints { $0.leading.trailing.equalToSuperview() }
        }
    }

    // MARK: - Actions

    @objc private func trustTapped() {
        Logger.ui.infoFile("User tapped Trust on CLI verification")
        dismiss(animated: true) { [onResponse] in
            onResponse(true)
        }
    }

    @objc private func rejectTapped() {
        Logger.ui.infoFile("User tapped Reject on CLI verification")
        dismiss(animated: true) { [onResponse] in
            onResponse(false)
        }
    }
}
