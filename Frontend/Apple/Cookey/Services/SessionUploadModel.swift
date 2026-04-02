import Combine
import ConfigurableKit
import CryptoBox
import Foundation

@MainActor
final class SessionUploadModel: ObservableObject {
    enum LoadingState: Equatable {
        case checkingRequest(host: String)
        case loadingSeed(host: String)
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case validating(DeepLink)
        case browsing(DeepLink)
        case uploading
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var seedSession: CapturedSession?
    @Published var loadingState: LoadingState?
    @Published var shouldPresentPushExplanation = false

    private let pushCoordinator: PushRegistrationCoordinator?
    private let relayClientFactory: (URL) -> RelayClient
    private var pushExplanationContinuation: CheckedContinuation<Bool, Never>?

    init(pushCoordinator: PushRegistrationCoordinator?) {
        self.pushCoordinator = pushCoordinator
        relayClientFactory = { RelayClient(baseURL: $0) }
    }

    init(
        pushCoordinator: PushRegistrationCoordinator?,
        relayClientFactory: @escaping (URL) -> RelayClient
    ) {
        self.pushCoordinator = pushCoordinator
        self.relayClientFactory = relayClientFactory
    }

    func startScan() {
        phase = .scanning
    }

    func handleURL(_ url: URL) {
        guard let deepLink = DeepLink(url: url) else {
            phase = .failed("Invalid Cookey login link.")
            return
        }

        phase = .validating(deepLink)
        Task { await validateAndProceed(deepLink) }
    }

    func captureAndUpload(
        from browser: BrowserCaptureModel,
        deepLink: DeepLink
    ) async {
        do {
            let plaintext = try await browser.captureSessionPayloadData()
            await uploadCapturedSessionData(plaintext, deepLink: deepLink)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func uploadCapturedSessionData(
        _ plaintext: Data,
        deepLink: DeepLink
    ) async {
        phase = .uploading

        do {
            guard let recipientPublicKey = Data(base64Encoded: deepLink.recipientPublicKeyBase64) else {
                throw UploadError.invalidRecipientPublicKey
            }

            try Self.validateCapturedSessionData(plaintext)

            let sealed = try XSalsa20Poly1305Box.seal(
                plaintext: plaintext,
                recipientPublicKey: recipientPublicKey
            )

            let envelope = EncryptedSessionEnvelope(
                version: 1,
                algorithm: "x25519-xsalsa20poly1305",
                ephemeralPublicKey: sealed.ephemeralPublicKey.base64EncodedString(),
                nonce: sealed.nonce.base64EncodedString(),
                ciphertext: sealed.ciphertext.base64EncodedString(),
                capturedAt: Date()
            )

            try await relayClientFactory(deepLink.serverURL).uploadSession(
                rid: deepLink.rid,
                envelope: envelope
            )
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func respondToPushExplanation(allow: Bool) {
        shouldPresentPushExplanation = false
        pushExplanationContinuation?.resume(returning: allow)
        pushExplanationContinuation = nil
    }

    func resetToIdle() {
        seedSession = nil
        loadingState = nil
        shouldPresentPushExplanation = false
        phase = .idle
    }

    private func validateAndProceed(_ deepLink: DeepLink) async {
        let host = deepLink.serverURL.host() ?? deepLink.serverURL.absoluteString

        do {
            loadingState = .checkingRequest(host: host)
            let status = try await relayClientFactory(deepLink.serverURL)
                .fetchRequestStatus(rid: deepLink.rid)

            if status.isExpired {
                phase = .failed(String(localized: "This login request has expired."))
                return
            }

            if deepLink.requestType == .refresh {
                loadingState = .loadingSeed(host: host)
                await loadSeed(for: deepLink)
                guard phase == .validating(deepLink) else { return }
            }

            try await preparePushSupport(for: deepLink)

            try? await Task.sleep(for: .seconds(1))
            loadingState = nil
            phase = .browsing(deepLink)
        } catch {
            loadingState = nil
            let nsError = error as NSError
            if nsError.domain == "Cookey.RelayClient", nsError.code == 404 || nsError.code == 410 {
                phase = .failed(String(localized: "This login request has expired or does not exist."))
            } else {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func loadSeed(for deepLink: DeepLink) async {
        do {
            guard let encrypted = try await relayClientFactory(deepLink.serverURL)
                .fetchSeedSession(rid: deepLink.rid)
            else {
                return
            }

            let deviceSecretKey = try DeviceKeyManager.secretKey()
            guard
                let ephemeralPublicKey = Data(base64Encoded: encrypted.ephemeralPublicKey),
                let nonce = Data(base64Encoded: encrypted.nonce),
                let ciphertext = Data(base64Encoded: encrypted.ciphertext)
            else {
                throw UploadError.invalidSessionPayload
            }

            let plaintext = try XSalsa20Poly1305Box.open(
                ciphertext: ciphertext,
                nonce: nonce,
                ephemeralPublicKey: ephemeralPublicKey,
                recipientSecretKey: deviceSecretKey
            )

            seedSession = try JSONDecoder().decode(CapturedSession.self, from: plaintext)
        } catch {
            phase = .failed("Failed to load seed session: \(error.localizedDescription)")
        }
    }

    private func preparePushSupport(for deepLink: DeepLink) async throws {
        guard PushRegistrationCoordinator.isSupported, let pushCoordinator else {
            return
        }

        let allowRefresh: Bool = ConfigurableKit.value(
            forKey: SettingsViewController.allowRefreshKey,
            defaultValue: false
        )

        if allowRefresh {
            try await pushCoordinator.ensurePushToken(
                serverURL: deepLink.serverURL,
                deviceID: deepLink.deviceID,
                requestAuthorizationIfNeeded: false
            )
            return
        }

        let wantsPush = await requestPushExplanation()
        guard wantsPush else { return }

        try await pushCoordinator.ensurePushToken(
            serverURL: deepLink.serverURL,
            deviceID: deepLink.deviceID,
            requestAuthorizationIfNeeded: true
        )

        ConfigurableKit.set(value: true, forKey: SettingsViewController.allowRefreshKey)
    }

    private func requestPushExplanation() async -> Bool {
        await withCheckedContinuation { continuation in
            pushExplanationContinuation = continuation
            shouldPresentPushExplanation = true
        }
    }

    static func validateCapturedSessionData(_ sessionData: Data) throws {
        guard !sessionData.isEmpty else {
            throw UploadError.emptySessionPayload
        }

        guard
            let object = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
            object["cookies"] != nil,
            object["origins"] != nil
        else {
            throw UploadError.invalidSessionPayload
        }
    }

    static func encodeCapturedSession(_ session: CapturedSession) throws -> Data {
        let data = try JSONEncoder().encode(session)
        try validateCapturedSessionData(data)
        return data
    }
}
