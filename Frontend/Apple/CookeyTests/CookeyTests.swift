import Clibsodium
@testable import Cookey
import CryptoBox
import Foundation
import Sodium
import Testing

@Suite(.serialized)
@MainActor
struct CookeyTests {
    @Test("DeepLink parses a valid login URL")
    func parsesDeepLink() throws {
        let url = try #require(
            URL(string: "cookey://login?rid=r_123&server=https%3A%2F%2Fapi.cookey.sh&target=https%3A%2F%2Fwww.qaq.wiki%2Fwp-admin&pubkey=U%2FuenIM6CaBBb3VLlp94N44EPuF8vQacUuzRfo27Lxk%3D&device_id=device-123")
        )

        let deepLink = try #require(DeepLink(url: url))
        #expect(deepLink.rid == "r_123")
        #expect(deepLink.serverURL == URL(string: "https://api.cookey.sh"))
        #expect(deepLink.targetURL == URL(string: "https://www.qaq.wiki/wp-admin"))
        #expect(deepLink.recipientPublicKeyBase64 == "U/uenIM6CaBBb3VLlp94N44EPuF8vQacUuzRfo27Lxk=")
        #expect(deepLink.deviceID == "device-123")
        #expect(deepLink.requestType == .login)
    }

    @Test(
        "validateCapturedSessionData rejects malformed payloads",
        arguments: [
            Data(),
            Data("{}".utf8),
            Data(#"{"cookies":[]}"#.utf8),
            Data(#"{"origins":[]}"#.utf8),
            Data("[]".utf8),
        ]
    )
    func rejectsMalformedCapturedPayload(_ payload: Data) throws {
        #expect(throws: Error.self) {
            try SessionUploadModel.validateCapturedSessionData(payload)
        }
    }

    @Test("validateCapturedSessionData accepts cookies + origins payload")
    func acceptsCapturedPayload() throws {
        let payload = Data(
            #"""
            {
              "cookies": [
                {
                  "name": "wordpress_test_cookie",
                  "value": "WP%20Cookie%20check",
                  "domain": "www.qaq.wiki",
                  "path": "/",
                  "expires": -1,
                  "httpOnly": true,
                  "secure": true,
                  "sameSite": "Lax"
                }
              ],
              "origins": [
                {
                  "origin": "https://www.qaq.wiki",
                  "localStorage": [
                    {
                      "name": "dracula_mode",
                      "value": "dark"
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )

        try SessionUploadModel.validateCapturedSessionData(payload)
    }

    @Test("encodeCapturedSession preserves browser session JSON")
    func encodesCapturedSession() throws {
        let capturedSession = CapturedSession(
            cookies: [
                CapturedCookie(
                    name: "wordpress_test_cookie",
                    value: "WP%20Cookie%20check",
                    domain: "www.qaq.wiki",
                    path: "/",
                    expires: -1,
                    httpOnly: true,
                    secure: true,
                    sameSite: "Lax"
                ),
                CapturedCookie(
                    name: "cf_clearance",
                    value: "token",
                    domain: ".qaq.wiki",
                    path: "/",
                    expires: 1_806_582_709,
                    httpOnly: true,
                    secure: true,
                    sameSite: "Lax"
                ),
            ],
            origins: [
                CapturedOrigin(
                    origin: "https://www.qaq.wiki",
                    localStorage: [
                        CapturedStorageItem(name: "dracula_mode", value: "dark"),
                    ]
                ),
            ],
            deviceInfo: nil
        )

        let payload = try SessionUploadModel.encodeCapturedSession(capturedSession)
        let decoded = try JSONDecoder().decode(CapturedSession.self, from: payload)

        #expect(payload.count > 100)
        #expect(decoded == capturedSession)
    }

    @Test("uploadCapturedSessionData posts decryptable envelope")
    func uploadsDecryptableEnvelope() async throws {
        let sodium = Sodium()
        let recipient = try #require(sodium.box.keyPair())
        let serverURL = try #require(URL(string: "https://api.cookey.test/\(UUID().uuidString)"))

        var components = URLComponents()
        components.scheme = "cookey"
        components.host = "login"
        components.queryItems = [
            URLQueryItem(name: "rid", value: "r_test_upload"),
            URLQueryItem(name: "server", value: serverURL.absoluteString),
            URLQueryItem(name: "target", value: "https://www.qaq.wiki/wp-admin"),
            URLQueryItem(name: "pubkey", value: Data(recipient.publicKey).base64EncodedString()),
            URLQueryItem(name: "device_id", value: "device-test"),
        ]

        let deepLinkURL = try #require(components.url)
        let deepLink = try #require(DeepLink(url: deepLinkURL))

        let capturedSession = CapturedSession(
            cookies: [
                CapturedCookie(
                    name: "wordpress_test_cookie",
                    value: "WP%20Cookie%20check",
                    domain: "www.qaq.wiki",
                    path: "/",
                    expires: -1,
                    httpOnly: true,
                    secure: true,
                    sameSite: "Lax"
                ),
                CapturedCookie(
                    name: "cf_clearance",
                    value: "token",
                    domain: ".qaq.wiki",
                    path: "/",
                    expires: 1_806_582_709,
                    httpOnly: true,
                    secure: true,
                    sameSite: "Lax"
                ),
            ],
            origins: [
                CapturedOrigin(
                    origin: "https://www.qaq.wiki",
                    localStorage: [
                        CapturedStorageItem(name: "dracula_mode", value: "dark"),
                    ]
                ),
            ],
            deviceInfo: nil
        )
        let plaintext = try SessionUploadModel.encodeCapturedSession(capturedSession)

        let requestBox = LockedBox<RecordedRequest?>(nil)

        NotificationPromptStore.store(.accepted, for: serverURL)

        let model = SessionUploadModel(
            pushCoordinator: nil,
            relayClientFactory: { baseURL in
                RelayClient(
                    baseURL: baseURL,
                    requestExecutor: { request in
                        let recordedRequest = RecordedRequest(
                            method: request.httpMethod,
                            url: request.url,
                            body: request.httpBody
                        )
                        requestBox.withLock { $0 = recordedRequest }
                        let response = HTTPURLResponse(
                            url: baseURL,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"]
                        )!
                        return (Data(), response)
                    }
                )
            }
        )
        await model.uploadCapturedSessionData(plaintext, deepLink: deepLink)

        let request = try #require(requestBox.withLock { $0 })
        #expect(request.method == "POST")
        #expect(request.url?.path == "\(serverURL.path)/v1/requests/\(deepLink.rid)/session")
        let body = try #require(request.body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedSessionEnvelope.self, from: body)
        let ciphertext = try #require(Data(base64Encoded: envelope.ciphertext))
        let nonce = try #require(Data(base64Encoded: envelope.nonce))
        let ephemeralPublicKey = try #require(Data(base64Encoded: envelope.ephemeralPublicKey))

        var sharedSecret = [UInt8](repeating: 0, count: Int(crypto_scalarmult_bytes()))
        var recipientSecretKey = recipient.secretKey
        var ephemeralPublicKeyBytes = [UInt8](ephemeralPublicKey)
        #expect(
            crypto_scalarmult(
                &sharedSecret,
                &recipientSecretKey,
                &ephemeralPublicKeyBytes
            ) == 0
        )

        let opened = try XSalsa20Poly1305Box.open(
            ciphertext: ciphertext,
            nonce: nonce,
            sharedSecret: Data(sharedSecret)
        )

        #expect(envelope.version == 1)
        #expect(envelope.algorithm == "x25519-xsalsa20poly1305")
        #expect(opened == plaintext)

        #expect(model.phase == .done)
    }

    @Test("PushRegistrationCoordinator stores token for waiting registration")
    func coordinatorStoresWaitingToken() async throws {
        PushTokenStore.currentToken = nil
        PushTokenStore.currentEnvironment = nil
        let coordinator = PushRegistrationCoordinator()

        let serverURL = try #require(URL(string: "https://relay.cookey.test"))
        coordinator.state = .waitingForToken(serverURL: serverURL, deviceID: "device-1")

        await coordinator.handleRegisteredDeviceToken(Data([0x01, 0x02, 0x03]))

        #expect(PushTokenStore.currentToken == "010203")
        #expect(PushTokenStore.currentEnvironment != nil)
        #expect(coordinator.state == .idle)
    }

    @Test("PushRegistrationCoordinator refreshes stored token without relay registration")
    func coordinatorRefreshesStoredToken() async {
        PushTokenStore.currentToken = nil
        PushTokenStore.currentEnvironment = nil
        let coordinator = PushRegistrationCoordinator()

        await coordinator.handleRegisteredDeviceToken(Data([0xAA, 0xBB]))

        #expect(PushTokenStore.currentToken == "aabb")
    }
}
