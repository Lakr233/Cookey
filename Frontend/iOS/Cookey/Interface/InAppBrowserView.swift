import Observation
import SwiftUI
import WebKit

struct InAppBrowserView: View {
    let deepLink: DeepLink
    let onCaptured: ([CapturedCookie], [CapturedOrigin]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var browser: BrowserCaptureModel

    init(
        deepLink: DeepLink,
        onCaptured: @escaping ([CapturedCookie], [CapturedOrigin]) async -> Void
    ) {
        self.deepLink = deepLink
        self.onCaptured = onCaptured
        _browser = State(initialValue: BrowserCaptureModel(targetURL: deepLink.targetURL))
    }

    var body: some View {
        NavigationStack {
            BrowserWebView(webView: browser.webView)
                .overlay(alignment: .top) {
                    if let errorMessage = browser.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.top, 12)
                    }
                }
                .navigationTitle(browser.pageTitle.isEmpty ? "Cookey" : browser.pageTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                browser.isTransferring = true
                                defer { browser.isTransferring = false }

                                do {
                                    let (cookies, origins) = try await browser.captureSession()
                                    await onCaptured(cookies, origins)
                                } catch {
                                    browser.errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            if browser.isTransferring {
                                ProgressView()
                            } else {
                                Text("Transfer Session")
                            }
                        }
                        .disabled(browser.isTransferring)
                    }
                }
        }
    }
}

@MainActor
@Observable
final class BrowserCaptureModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    var errorMessage: String?
    var isTransferring = false
    var pageTitle = ""

    private let targetURL: URL

    init(targetURL: URL) {
        self.targetURL = targetURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.load(URLRequest(url: targetURL))
    }

    func captureSession() async throws -> ([CapturedCookie], [CapturedOrigin]) {
        let cookies = await capturedCookies()
        let origins = try await capturedOrigins()
        return (cookies, origins)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageTitle = webView.title ?? "Cookey"
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
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
}

#if os(iOS)
private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}
#elseif os(macOS)
private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}
#endif
