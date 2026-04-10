import WebKit

extension BrowserCaptureModel: WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor _: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Prevent universal links from hijacking the login flow (e.g., "Sign in with Google"
        // opening the Google app). Firefox iOS, Brave, and DuckDuckGo all use this undocumented
        // rawValue+2 trick to tell WebKit to suppress universal link activation.
        if let policy = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) {
            decisionHandler(policy)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        pageTitle = webView.title ?? "Cookey"
        pageDomain = webView.url?.host ?? ""
        if !initialLoadComplete {
            initialLoadComplete = true
        }
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
    }
}
