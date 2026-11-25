import SnapKit
import UIKit

/// Keeps text and controls off the fold of a foldable iPhone while it is
/// partially folded. Pin it to the edges of the view that lays out the content
/// and place the content in `contentRegion` and `controlRegion`.
///
/// Without a fold, which is the case flat open, closed and on every other
/// device, both regions span the full height of the view and the width of its
/// safe area, so the layout is the same as laying out against the view.
final class FoldRegionView: UIView {
    /// The region for the main content. Left of a vertical fold, above a
    /// horizontal fold.
    let contentRegion = UILayoutGuide()
    /// The region for controls pinned to the bottom. Left of a vertical fold,
    /// below a horizontal fold.
    let controlRegion = UILayoutGuide()

    private var foldFrame: CGRect?
    private var previousSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addLayoutGuide(contentRegion)
        addLayoutGuide(controlRegion)
        layoutRegions()
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, _ in
                self?.setNeedsUpdateConstraints()
            })
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size {
            previousSize = bounds.size
            setNeedsUpdateConstraints()
        }
    }

    override func updateConstraints() {
        var frame: CGRect?
        if #available(iOS 27.1, *) {
            frame = reservedRegions(kind: .division).first?.frame
        }
        if frame != foldFrame {
            foldFrame = frame
            layoutRegions()
        }
        super.updateConstraints()
    }

    private func layoutRegions() {
        let safeArea = safeAreaLayoutGuide
        guard let foldFrame else {
            for region in [contentRegion, controlRegion] {
                region.snp.remakeConstraints {
                    $0.top.bottom.equalTo(self)
                    $0.left.right.equalTo(safeArea)
                }
            }
            return
        }
        if foldFrame.width < foldFrame.height {
            for region in [contentRegion, controlRegion] {
                region.snp.remakeConstraints {
                    $0.top.bottom.equalTo(self)
                    $0.left.equalTo(safeArea)
                    $0.right.equalTo(self.snp.left).offset(foldFrame.minX)
                }
            }
        } else {
            contentRegion.snp.remakeConstraints {
                $0.top.equalTo(safeArea)
                $0.left.right.equalTo(safeArea)
                $0.bottom.equalTo(self.snp.top).offset(foldFrame.minY)
            }
            controlRegion.snp.remakeConstraints {
                $0.top.equalTo(self.snp.top).offset(foldFrame.maxY)
                $0.left.right.equalTo(safeArea)
                $0.bottom.equalTo(self)
            }
        }
    }
}
