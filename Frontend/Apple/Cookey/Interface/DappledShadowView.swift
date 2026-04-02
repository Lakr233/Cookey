import UIKit

/// A full-screen overlay that renders slowly drifting, dappled leaf shadows.
///
/// Uses procedurally generated elliptical blobs composited with `multiply`
/// blend mode and animated via Core Animation for a gentle, organic feel.
class DappledShadowView: UIView {
    private let patternLayer = CALayer()

    private static let blobCount = 40
    private static let canvasScale: CGFloat = 2.5
    private static let driftDuration: CFTimeInterval = 28
    private static let rotationDuration: CFTimeInterval = 50

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.compositingFilter = "multiplyBlendMode"
        clipsToBounds = true
        alpha = 0.10

        layer.addSublayer(patternLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let canvasSize = CGSize(
            width: size.width * Self.canvasScale,
            height: size.height * Self.canvasScale
        )

        patternLayer.frame = CGRect(
            x: -(canvasSize.width - size.width) / 2,
            y: -(canvasSize.height - size.height) / 2,
            width: canvasSize.width,
            height: canvasSize.height
        )

        redrawPattern(in: canvasSize)
        applyAnimations()
    }

    private func redrawPattern(in size: CGSize) {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let gc = ctx.cgContext
            // White base — multiply with white is identity
            UIColor.white.setFill()
            gc.fill(CGRect(origin: .zero, size: size))

            let rng = { (lo: CGFloat, hi: CGFloat) -> CGFloat in
                CGFloat.random(in: lo ... hi)
            }

            for _ in 0 ..< Self.blobCount {
                let cx = rng(0, size.width)
                let cy = rng(0, size.height)
                let rx = rng(30, 100)
                let ry = rng(20, 80)
                let angle = rng(0, .pi)
                let alpha = rng(0.15, 0.45)

                gc.saveGState()
                gc.translateBy(x: cx, y: cy)
                gc.rotate(by: angle)

                let rect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
                gc.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
                gc.fillEllipse(in: rect)

                gc.restoreGState()
            }

            // Soften the pattern with a gaussian blur
            if let ciImage = CIImage(image: UIImage(cgImage: gc.makeImage()!)) {
                let blur = CIFilter(name: "CIGaussianBlur", parameters: [
                    kCIInputImageKey: ciImage,
                    kCIInputRadiusKey: 24,
                ])!
                let ciCtx = CIContext()
                if let output = blur.outputImage,
                   let blurred = ciCtx.createCGImage(output, from: ciImage.extent)
                {
                    gc.clear(CGRect(origin: .zero, size: size))
                    gc.draw(blurred, in: CGRect(origin: .zero, size: size))
                }
            }
        }

        patternLayer.contents = image.cgImage
    }

    private func applyAnimations() {
        patternLayer.removeAllAnimations()

        let drift = CABasicAnimation(keyPath: "position")
        let center = patternLayer.position
        let dx: CGFloat = bounds.width * 0.15
        let dy: CGFloat = bounds.height * 0.10
        drift.fromValue = CGPoint(x: center.x - dx, y: center.y - dy)
        drift.toValue = CGPoint(x: center.x + dx, y: center.y + dy)
        drift.duration = Self.driftDuration
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        rotate.fromValue = -CGFloat.pi * 0.03
        rotate.toValue = CGFloat.pi * 0.03
        rotate.duration = Self.rotationDuration
        rotate.autoreverses = true
        rotate.repeatCount = .infinity
        rotate.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        patternLayer.add(drift, forKey: "drift")
        patternLayer.add(rotate, forKey: "rotate")
    }
}
