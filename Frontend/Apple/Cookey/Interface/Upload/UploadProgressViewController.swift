import Combine
import SnapKit
import Then
import UIKit

class UploadProgressViewController: UIViewController {
    private let sessionModel: SessionUploadModel
    private var cancellables = Set<AnyCancellable>()

    private let iconView = UIImageView().then {
        $0.contentMode = .scaleAspectFit
        $0.preferredSymbolConfiguration = .init(pointSize: 48, weight: .regular)
    }

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 22, weight: .bold)
        $0.textAlignment = .center
    }

    private let subtitleLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .footnote)
        $0.textColor = .secondaryLabel
        $0.textAlignment = .center
        $0.numberOfLines = 0
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
        navigationItem.hidesBackButton = true

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, subtitleLabel]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 8
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
        updateUI(for: sessionModel.phase)
    }

    // MARK: - Bindings

    private func bindModel() {
        sessionModel.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.updateUI(for: phase) }
            .store(in: &cancellables)
    }

    private func updateUI(for phase: SessionUploadModel.Phase) {
        switch phase {
        case .uploading:
            iconView.image = UIImage(systemName: "arrow.up.circle.fill")
            iconView.tintColor = .secondaryLabel
            iconView.addSymbolEffect(.pulse.wholeSymbol)
            titleLabel.text = String(localized: "Uploading session…")
            subtitleLabel.text = String(localized: "Encrypting and sending your browser session.")
            navigationItem.rightBarButtonItem = nil

        case .done:
            iconView.removeAllSymbolEffects()
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            iconView.tintColor = .systemGreen
            titleLabel.text = String(localized: "Transfer complete")
            subtitleLabel.text = String(localized: "Your terminal can export the session now.")
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "Done"), style: .done,
                target: self, action: #selector(doneTapped),
            )

        case let .failed(message):
            iconView.removeAllSymbolEffects()
            iconView.image = UIImage(systemName: "xmark.octagon.fill")
            iconView.tintColor = .systemRed
            titleLabel.text = String(localized: "Transfer failed")
            subtitleLabel.text = message
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: String(localized: "Done"), style: .done,
                target: self, action: #selector(doneTapped),
            )

        default:
            break
        }
    }

    @objc private func doneTapped() {
        sessionModel.resetToIdle()
    }
}
