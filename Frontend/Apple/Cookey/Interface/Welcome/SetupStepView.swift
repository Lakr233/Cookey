import SnapKit
import Then
import UIKit

class SetupStepView: UIView {
    private let scrollView = UIScrollView().then {
        $0.showsVerticalScrollIndicator = false
        $0.alwaysBounceVertical = false
    }

    private let contentStack = UIStackView().then {
        $0.axis = .vertical
        $0.spacing = 16
        $0.alignment = .fill
    }

    private let titleLabel = UILabel().then {
        $0.font = .systemFont(ofSize: 28, weight: .bold)
        $0.textColor = .label
        $0.numberOfLines = 0
    }

    private let subtitleLabel = UILabel().then {
        $0.font = .preferredFont(forTextStyle: .body)
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 0
    }

    init(title: String, subtitle: String, accessory: UIView? = nil) {
        super.init(frame: .zero)

        titleLabel.text = title
        subtitleLabel.text = subtitle

        addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)

        contentStack.setCustomSpacing(12, after: titleLabel)

        if let accessory {
            contentStack.addArrangedSubview(accessory)
            contentStack.setCustomSpacing(24, after: subtitleLabel)
        }

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(80)
            make.leading.trailing.equalToSuperview().inset(32)
            make.bottom.lessThanOrEqualToSuperview().inset(16)
            make.width.equalTo(scrollView).offset(-64)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
