import UIKit

/// A full-screen overlay that renders slowly drifting, dappled leaf shadows.
///
/// Draws semi-transparent elliptical blobs on a clear background, softened
/// with gaussian blur, then animates with slow drift + rotation.
class DappledShadowView: UIView {
    private let patternLayer = CALayer()

    private static let blobCount = 45
    private static let canvasScale: CGFloat = 2.5
    private static let driftDuration: CFTimeInterval = 28
    private static let rotationDuration: CFTimeInterval = 50

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true

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

        if patternLayer.contents == nil {
            redrawPattern(in: canvasSize)
            applyAnimations()
        }
    }

    private func redrawPattern(in size: CGSize) {
        // Draw blobs onto an opaque white canvas first (needed for CIGaussianBlur),
        // then composite onto a clear image using .multiply so white becomes transparent.
        let opaqueRenderer = UIGraphicsImageRenderer(size: size)
        let opaqueImage = opaqueRenderer.image { ctx in
            let gc = ctx.cgContext
            UIColor.white.setFill()
            gc.fill(CGRect(origin: .zero, size: size))

            for _ in 0 ..< Self.blobCount {
                let cx = CGFloat.random(in: 0 ... size.width)
                let cy = CGFloat.random(in: 0 ... size.height)
                let rx = CGFloat.random(in: 35 ... 110)
                let ry = CGFloat.random(in: 25 ... 85)
                let angle = CGFloat.random(in: 0 ... .pi)
                let a = CGFloat.random(in: 0.25 ... 0.6)

                gc.saveGState()
                gc.translateBy(x: cx, y: cy)
                gc.rotate(by: angle)
                gc.setFillColor(UIColor.black.withAlphaComponent(a).cgColor)
                gc.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                gc.restoreGState()
            }
        }

        // Apply gaussian blur
        guard let ciInput = CIImage(image: opaqueImage),
              let blur = CIFilter(name: "CIGaussianBlur", parameters: [
                  kCIInputImageKey: ciInput,
                  kCIInputRadiusKey: 28,
              ]),
              let blurredCI = blur.outputImage
        else {
            patternLayer.contents = opaqueImage.cgImage
            return
        }

        let ciCtx = CIContext()
        guard let blurredCG = ciCtx.createCGImage(blurredCI, from: ciInput.extent) else {
            patternLayer.contents = opaqueImage.cgImage
            return
        }

        // Composite: draw blurred image with .multiply onto clear background.
        // White areas become transparent, dark blobs become semi-transparent shadows.
        let finalRenderer = UIGraphicsImageRenderer(size: size)
        let finalImage = finalRenderer.image { ctx in
            let gc = ctx.cgContext
            // Start with clear background
            gc.clear(CGRect(origin: .zero, size: size))
            // Draw the blurred pattern with multiply — white pixels drop out
            gc.setBlendMode(.multiply)
            gc.draw(blurredCG, in: CGRect(origin: .zero, size: size))
        }

        patternLayer.contents = finalImage.cgImage
        patternLayer.opacity = 0.12
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
