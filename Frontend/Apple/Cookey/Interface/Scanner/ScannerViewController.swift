import AVFoundation
import SnapKit
import UIKit

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let sessionModel: SessionUploadModel
    private let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "Cookey.Scanner.capture")
    private var didScan = false
    private var captureDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    private lazy var containerView = ScannerContainerView()

    init(sessionModel: SessionUploadModel) {
        self.sessionModel = sessionModel
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Scan")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(containerView)
        containerView.snp.makeConstraints {
            $0.centerX.equalTo(view.safeAreaLayoutGuide)
            $0.centerY.equalToSuperview().priority(.high)
            $0.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(32).priority(.high)
            $0.leading.greaterThanOrEqualTo(view.safeAreaLayoutGuide).inset(32)
            $0.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide).inset(32)
            $0.top.greaterThanOrEqualTo(view.safeAreaLayoutGuide).inset(16)
            $0.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide).inset(16)
            $0.height.equalTo(containerView.snp.width)
        }
        containerView.layer.cornerRadius = 16
        containerView.clipsToBounds = true
        containerView.onOpenSettings = {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }

        containerView.previewLayer.session = captureSession
        startCamera()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPreviewRotationIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopCamera()
        if isMovingFromParent, sessionModel.phase == .scanning {
            sessionModel.resetToIdle()
        }
    }

    // MARK: - Camera

    private func startCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureSession()
                } else {
                    DispatchQueue.main.async {
                        self?.containerView.showMessage(String(localized: "Camera access is required to scan Cookey QR codes."), showSettingsButton: true)
                    }
                }
            }
        default:
            containerView.showMessage(String(localized: "Camera access is required to scan Cookey QR codes."), showSettingsButton: true)
        }
    }

    private func stopCamera() {
        captureQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    private func configureSession() {
        let delegate: AVCaptureMetadataOutputObjectsDelegate = self
        captureQueue.async { [weak self] in
            guard let self else { return }
            guard captureSession.inputs.isEmpty, captureSession.outputs.isEmpty else {
                if !captureSession.isRunning { captureSession.startRunning() }
                return
            }

            guard let device = AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async {
                    self.containerView.showMessage(String(localized: "No camera is available on this device."))
                }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureMetadataOutput()

                captureSession.beginConfiguration()
                if captureSession.canAddInput(input) { captureSession.addInput(input) }
                if captureSession.canAddOutput(output) {
                    captureSession.addOutput(output)
                    output.setMetadataObjectsDelegate(delegate, queue: .main)
                    output.metadataObjectTypes = [.qr]
                }
                captureSession.commitConfiguration()
                captureSession.startRunning()
                DispatchQueue.main.async {
                    self.captureDevice = device
                    self.startPreviewRotationIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    self.containerView.showMessage(String(localized: "Cookey could not start the camera scanner."))
                }
            }
        }
    }

    /// Keeps the preview upright when the interface rotates or the app moves
    /// to another display, for example when the device folds or unfolds.
    private func startPreviewRotationIfNeeded() {
        guard rotationCoordinator == nil,
              let captureDevice,
              view.window != nil
        else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: captureDevice,
            previewLayer: containerView.previewLayer,
        )
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new],
        ) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async {
                self?.applyPreviewRotation(angle)
            }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = containerView.previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle)
        else { return }
        connection.videoRotationAngle = angle
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection,
    ) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              let url = URL(string: value),
              url.scheme?.lowercased() == "cookey"
        else { return }

        didScan = true
        stopCamera()
        sessionModel.handleURL(url)
    }
}
