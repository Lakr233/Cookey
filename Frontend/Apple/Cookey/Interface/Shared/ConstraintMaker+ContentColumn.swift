import SnapKit
import UIKit

extension ConstraintMaker {
    /// Lays out a centered content column inside `region`, usually a safe area
    /// layout guide or a region of a `FoldRegionView`.
    ///
    /// Each edge follows its own side of the region, so the column stays clear
    /// of a vertical bar on either side of the display.
    func contentColumn(in region: UILayoutGuide, inset: CGFloat = 32) {
        centerX.equalTo(region)
        leading.greaterThanOrEqualTo(region).inset(inset)
        trailing.lessThanOrEqualTo(region).inset(inset)
        leading.trailing.equalTo(region).inset(inset).priority(.high)
    }
}
