#if os(iOS)
import AVFoundation
import SwiftUI

struct ScannerView: UIViewRepresentable {
    let onScanned: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    func makeUIView(context: Context) -> ScannerContainerView {
        let view = ScannerContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: ScannerContainerView, context: Context) {
    }

    static func dismantleUIView(_ uiView: ScannerContainerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "Cookey.ScannerView.capture")
        private let onScanned: (URL) -> Void
        private weak var containerView: ScannerContainerView?
        private var didScan = false

        init(onScanned: @escaping (URL) -> Void) {
            self.onScanned = onScanned
        }

        func attach(to view: ScannerContainerView) {
            containerView = view
            view.previewLayer.session = session
        }

        func start() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureSessionIfNeeded()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.configureSessionIfNeeded()
                    } else {
                        DispatchQueue.main.async {
                            self.containerView?.showMessage("Camera access is required to scan Cookey QR codes.")
                        }
                    }
                }
            default:
                containerView?.showMessage("Camera access is required to scan Cookey QR codes.")
            }
        }

        func stop() {
            queue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        }

        private func configureSessionIfNeeded() {
            queue.async {
                guard self.session.inputs.isEmpty, self.session.outputs.isEmpty else {
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    return
                }

                guard let device = AVCaptureDevice.default(for: .video) else {
                    DispatchQueue.main.async {
                        self.containerView?.showMessage("No camera is available on this device.")
                    }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureMetadataOutput()

                    self.session.beginConfiguration()
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                    }
                    if self.session.canAddOutput(output) {
                        self.session.addOutput(output)
                        output.setMetadataObjectsDelegate(self, queue: .main)
                        output.metadataObjectTypes = [.qr]
                    }
                    self.session.commitConfiguration()
                    self.session.startRunning()
                } catch {
                    DispatchQueue.main.async {
                        self.containerView?.showMessage("Cookey could not start the camera scanner.")
                    }
                }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan else {
                return
            }

            guard
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                object.type == .qr,
                let value = object.stringValue,
                let url = URL(string: value),
                DeepLink(url: url) != nil
            else {
                return
            }

            didScan = true
            stop()
            onScanned(url)
        }
    }
}

final class ScannerContainerView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    func showMessage(_ message: String) {
        messageLabel.text = message
        messageLabel.isHidden = false
    }
}
#endif
