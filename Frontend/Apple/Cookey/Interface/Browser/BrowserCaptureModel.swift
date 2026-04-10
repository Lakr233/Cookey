import Combine
import Foundation
import WebKit

@MainActor
final class BrowserCaptureModel: NSObject, ObservableObject, WKScriptMessageHandler {
    enum CaptureError: LocalizedError {
        case emptyPayload
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .emptyPayload:
                String(localized: "The captured browser session was empty.")
            case .invalidPayload:
                String(localized: "The captured browser session could not be encoded.")
            }
        }
    }

    let webView: WKWebView

    @Published var errorMessage: String?
    @Published var isTransferring = false
    @Published var pageTitle = ""
    @Published var pageDomain = ""
    @Published var passkeyAlertPresented = false
    @Published var initialLoadComplete = false

    private let targetURL: URL
    private let deviceID: String

    init(targetURL: URL, deviceID: String) {
        self.targetURL = targetURL
        self.deviceID = deviceID
        pageDomain = targetURL.host() ?? ""
        Logger.browser.infoFile("Creating browser capture model for target \(targetURL.host() ?? targetURL.absoluteString) without seed session")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        #if os(iOS) || os(visionOS)
            configuration.allowsInlineMediaPlayback = true
            configuration.ignoresViewportScaleLimits = true
            configuration.applicationNameForUserAgent = "FxiOS/149.2 Safari/604.1"
        #endif
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        Self.installPasskeyIntercept(on: configuration.userContentController)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .systemBackground
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, iOS 16.4, tvOS 16.4, *) {
            webView.isInspectable = true
        }
        super.init()
        configuration.userContentController.add(self, contentWorld: .defaultClient, name: Self.passkeyMessageHandler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: targetURL))
    }

    init(targetURL: URL, deviceID: String, seedSession: CapturedSession) {
        self.targetURL = targetURL
        self.deviceID = deviceID
        pageDomain = targetURL.host() ?? ""
        Logger.browser.infoFile("Creating browser capture model for target \(targetURL.host() ?? targetURL.absoluteString) with seed session cookies=\(seedSession.cookies.count) origins=\(seedSession.origins.count)")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        #if os(iOS) || os(visionOS)
            configuration.allowsInlineMediaPlayback = true
            configuration.ignoresViewportScaleLimits = true
            configuration.applicationNameForUserAgent = "FxiOS/149.2 Safari/604.1"
        #endif
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if let localStorageScript = Self.localStorageInjectionScript(from: seedSession.origins) {
            let userScript = WKUserScript(
                source: localStorageScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(userScript)
        }

        Self.installPasskeyIntercept(on: configuration.userContentController)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .systemBackground
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, iOS 16.4, tvOS 16.4, *) {
            webView.isInspectable = true
        }
        super.init()
        configuration.userContentController.add(self, contentWorld: .defaultClient, name: Self.passkeyMessageHandler)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        Task { @MainActor [weak webView] in
            let cookieStore = configuration.websiteDataStore.httpCookieStore
            for cookie in Self.httpCookies(from: seedSession.cookies) {
                await Self.setCookie(cookie, in: cookieStore)
            }
            _ = await Self.allCookies(in: cookieStore)
            webView?.load(URLRequest(url: targetURL))
        }
    }

    func captureSessionPayloadData() async throws -> Data {
        let cookies = await capturedCookies()
        let origins = try await capturedOrigins()
        let deviceInfo = try currentDeviceInfo()
        Logger.browser.infoFile("Captured browser state with cookies=\(cookies.count) origins=\(origins.count) deviceInfoPresent=\(deviceInfo != nil)")

        let session = CapturedSession(cookies: cookies, origins: origins, deviceInfo: deviceInfo)
        let data = try sanitizeCapturedSessionPayload(session)

        guard !data.isEmpty else {
            throw CaptureError.emptyPayload
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["cookies"] != nil,
            object["origins"] != nil
        else {
            throw CaptureError.invalidPayload
        }

        return data
    }

    static func localStorageInjectionScript(from origins: [CapturedOrigin]) -> String? {
        var blocks: [String] = []

        for origin in origins {
            guard !origin.localStorage.isEmpty else { continue }
            guard
                let originString = Self.jsonLiteral(origin.origin)
            else {
                continue
            }

            var items: [String] = []
            for item in origin.localStorage {
                guard
                    let keyString = Self.jsonLiteral(item.name),
                    let valueString = Self.jsonLiteral(item.value)
                else {
                    continue
                }
                items.append("try{window.localStorage.setItem(\(keyString),\(valueString))}catch(e){}")
            }

            blocks.append("if(window.location.origin===\(originString)){\(items.joined(separator: ";"))}")
        }

        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }

    static func httpCookies(from captured: [CapturedCookie]) -> [HTTPCookie] {
        captured.compactMap { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .domain: cookie.domain,
                .path: cookie.path,
            ]

            if cookie.expires > 0 {
                properties[.expires] = Date(timeIntervalSince1970: cookie.expires)
            }
            if cookie.secure {
                properties[.secure] = "TRUE"
            }
            if cookie.httpOnly {
                properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
            }
            if !cookie.sameSite.isEmpty {
                properties[.sameSitePolicy] = cookie.sameSite
            }

            return HTTPCookie(properties: properties)
        }
    }

    private func sanitizeCapturedSessionPayload(_ session: CapturedSession) throws -> Data {
        let encoded = try JSONEncoder().encode(session)
        let sanitizedSession = try JSONDecoder().decode(CapturedSession.self, from: encoded)
        return try JSONEncoder().encode(sanitizedSession)
    }

    private func capturedCookies() async -> [CapturedCookie] {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }

        return cookies.map { cookie in
            CapturedCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expires: cookie.expiresDate?.timeIntervalSince1970 ?? -1,
                httpOnly: cookie.isHTTPOnly,
                secure: cookie.isSecure,
                sameSite: cookie.properties?[.sameSitePolicy] as? String ?? "Lax"
            )
        }
    }

    private func capturedOrigins() async throws -> [CapturedOrigin] {
        let script = """
        JSON.stringify(Object.keys(window.localStorage).map(function(key) {
            return { name: key, value: window.localStorage.getItem(key) || "" };
        }))
        """

        let rawItems = try await webView.evaluateJavaScript(script)
        let itemsJSON = rawItems as? String ?? "[]"
        let items = try JSONDecoder().decode([CapturedStorageItem].self, from: Data(itemsJSON.utf8))
        Logger.browser.debugFile("Captured \(items.count) localStorage items from \(webView.url?.host() ?? targetURL.host() ?? targetURL.absoluteString)")

        let currentURL = webView.url ?? targetURL
        return [CapturedOrigin(origin: originString(for: currentURL), localStorage: items)]
    }

    private func originString(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme ?? "https"
        let host = components?.host ?? url.host() ?? ""
        let port = components?.port

        let isDefaultPort =
            (scheme == "https" && port == 443) ||
            (scheme == "http" && port == 80)

        if let port, !isDefaultPort {
            return "\(scheme)://\(host):\(port)"
        }

        return "\(scheme)://\(host)"
    }

    private func currentDeviceInfo() throws -> DeviceInfo? {
        guard
            let token = PushTokenStore.currentToken,
            let environment = PushTokenStore.currentEnvironment
        else {
            Logger.push.debugFile("No APNs device info available for captured session")
            return nil
        }

        Logger.push.debugFile("Attaching APNs device info to captured session in \(environment) environment")
        return try DeviceInfo(
            deviceID: deviceID,
            apnToken: token,
            apnEnvironment: environment,
            publicKey: DeviceKeyManager.publicKeyBase64()
        )
    }

    private static func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private static func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    // MARK: - Passkey Intercept

    private static let passkeyMessageHandler = "passkeyInterceptHandler"

    /// Script A: Runs in the **page** content world so it can override `navigator.credentials`.
    /// Signals the native side by setting a DOM attribute on `<html>`, which is visible
    /// across all content worlds.
    private static let passkeyPageScript = """
    (function() {
        if (navigator.credentials) {
            var origCreate = navigator.credentials.create.bind(navigator.credentials);
            var origGet = navigator.credentials.get.bind(navigator.credentials);

            navigator.credentials.create = function(options) {
                if (options && options.publicKey) {
                    document.documentElement.setAttribute('data-ck-pk', Date.now().toString());
                    return Promise.reject(new DOMException("Passkey is not supported in this browser.", "NotAllowedError"));
                }
                return origCreate.apply(navigator.credentials, arguments);
            };

            navigator.credentials.get = function(options) {
                if (options && options.publicKey) {
                    document.documentElement.setAttribute('data-ck-pk', Date.now().toString());
                    return Promise.reject(new DOMException("Passkey is not supported in this browser.", "NotAllowedError"));
                }
                return origGet.apply(navigator.credentials, arguments);
            };
        }
    })();
    """

    /// Script B: Runs in the **defaultClient** content world where `messageHandlers` is registered.
    /// Watches the DOM attribute set by Script A and relays the signal to native code.
    private static let passkeyRelayScript = """
    (function() {
        function relay() {
            if (document.documentElement.hasAttribute('data-ck-pk')) {
                window.webkit.messageHandlers.passkeyInterceptHandler.postMessage('detected');
                document.documentElement.removeAttribute('data-ck-pk');
            }
        }
        var observer = new MutationObserver(function() { relay(); });
        observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-ck-pk'] });
        relay();
    })();
    """

    private static func installPasskeyIntercept(on controller: WKUserContentController) {
        // Script A: page world — overrides navigator.credentials
        let pageScript = WKUserScript(
            source: passkeyPageScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(pageScript)

        // Script B: defaultClient world — relays DOM signal to native via messageHandler
        let relayScript = WKUserScript(
            source: passkeyRelayScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .defaultClient
        )
        controller.addUserScript(relayScript)
    }

    nonisolated func userContentController(
        _: WKUserContentController,
        didReceive _: WKScriptMessage
    ) {
        Task { @MainActor in
            passkeyAlertPresented = true
        }
    }

    // MARK: - Helpers

    private static func jsonLiteral(_ string: String) -> String? {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [string]),
            let arrayString = String(data: data, encoding: .utf8),
            arrayString.count >= 2
        else {
            return nil
        }

        return String(arrayString.dropFirst().dropLast())
    }
}
