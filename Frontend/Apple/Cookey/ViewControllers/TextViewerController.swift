import SnapKit
import Then
import UIKit

class TextViewerController: UIViewController {
    private let textView = UITextView().then {
        $0.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        $0.isEditable = false
        $0.isSelectable = true
        $0.isScrollEnabled = true
        $0.textColor = .label
        $0.backgroundColor = .clear
        $0.textContainerInset = .init(top: 10, left: 10, bottom: 10, right: 10)
        $0.textContainer.lineFragmentPadding = .zero
        $0.showsVerticalScrollIndicator = true
    }

    init(title: String, text: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
        textView.text = text
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(textView)
        textView.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            primaryAction: UIAction { [weak self] _ in
                guard let text = self?.textView.text else { return }
                UIPasteboard.general.string = text
            }
        )
    }
}
