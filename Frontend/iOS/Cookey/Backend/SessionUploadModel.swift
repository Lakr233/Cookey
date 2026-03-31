import CryptoBox
import Foundation
import Observation

@MainActor
@Observable
final class SessionUploadModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case browsing(DeepLink)
        case uploading
        case done
        case failed(String)
        case apnOptIn(DeepLink)
    }

    var phase: Phase = .idle

    private let pushCoordinator: PushRegistrationCoordinator?

    init(pushCoordinator: PushRegistrationCoordinator?) {
        self.pushCoordinator = pushCoordinator
    }

    func startScan() {
        phase = .scanning
    }

    func handleURL(_ url: URL) {
        guard let deepLink = DeepLink(url: url) else {
            phase = .failed("Invalid Cookey login link.")
            return
        }

        phase = .browsing(deepLink)
    }

    func captureAndUpload(
        cookies: [CapturedCookie],
        origins: [CapturedOrigin],
        deepLink: DeepLink
    ) async {
        phase = .uploading

        do {
            guard let recipientPublicKey = Data(base64Encoded: deepLink.recipientPublicKeyBase64) else {
                throw SessionUploadError.invalidRecipientPublicKey
            }

            let plaintext = try JSONEncoder().encode(CapturedSession(cookies: cookies, origins: origins))
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

            try await APIClient(baseURL: deepLink.serverURL).uploadSession(
                rid: deepLink.rid,
                envelope: envelope
            )

            guard PushRegistrationCoordinator.isSupported else {
                phase = .done
                return
            }

            if APNPromptStateStore.response(for: deepLink.serverURL) != nil {
                phase = .done
            } else {
                phase = .apnOptIn(deepLink)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func acceptNotificationOptIn(for deepLink: DeepLink) async {
        APNPromptStateStore.store(.accepted, for: deepLink.serverURL)
        if let pushCoordinator {
            await pushCoordinator.beginRegistration(
                serverURL: deepLink.serverURL,
                deviceID: deepLink.deviceID
            )
        }
        phase = .done
    }

    func dismissSheet() {
        phase = .idle
    }
}

enum APNPromptResponse: String {
    case accepted
    case declined
}

enum APNPromptStateStore {
    static func response(for serverURL: URL) -> APNPromptResponse? {
        guard let rawValue = UserDefaults.standard.string(forKey: key(for: serverURL)) else {
            return nil
        }
        return APNPromptResponse(rawValue: rawValue)
    }

    static func store(_ response: APNPromptResponse, for serverURL: URL) {
        UserDefaults.standard.set(response.rawValue, forKey: key(for: serverURL))
    }

    private static func key(for serverURL: URL) -> String {
        "apn_prompt_state::\(serverURL.absoluteString)"
    }
}

private enum SessionUploadError: LocalizedError {
    case invalidRecipientPublicKey

    var errorDescription: String? {
        switch self {
        case .invalidRecipientPublicKey:
            return "The login request contains an invalid recipient key."
        }
    }
}
