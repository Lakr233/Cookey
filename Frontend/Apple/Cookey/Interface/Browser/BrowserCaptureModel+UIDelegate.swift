import SnapKit
import UIKit
import WebKit

extension BrowserCaptureModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            // If it's a regular target="_blank" link click without explicit popup dimensions,
            // just load it in the current webview instead of opening a drawer.
            if navigationAction.navigationType == .linkActivated && windowFeatures.width == nil && windowFeatures.height == nil {
                webView.load(navigationAction.request)
                return nil
            }

            // Many OAuth providers use window.open to open a popup, and then use window.opener.postMessage
            // to send the token back to the main window. WKWebView natively breaks window.opener unless
            // the popup is actually created as a separate WKWebView instance and returned from this delegate method.
            let popupWebView = WKWebView(frame: webView.bounds, configuration: configuration)
            popupWebView.uiDelegate = self
            popupWebView.navigationDelegate = webView.navigationDelegate
            popupWebView.customUserAgent = webView.customUserAgent
            popupWebView.allowsBackForwardNavigationGestures = true
            if #available(macOS 13.3, iOS 16.4, tvOS 16.4, *) {
                popupWebView.isInspectable = webView.isInspectable
            }

            let popupVC = UIViewController()
            popupVC.view.backgroundColor = .systemBackground
            popupVC.view.addSubview(popupWebView)
            popupWebView.snp.makeConstraints { $0.edges.equalToSuperview() }

            popupVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
                systemItem: .done,
                primaryAction: UIAction { [weak popupVC] _ in
                    popupVC?.dismiss(animated: true)
                }
            )

            let navVC = UINavigationController(rootViewController: popupVC)

            if let topVC = topViewController(for: webView.window) {
                topVC.present(navVC, animated: true)
            } else {
                webView.addSubview(popupWebView)
                popupWebView.snp.makeConstraints { $0.edges.equalToSuperview() }
            }

            return popupWebView
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let vc = findViewController(for: webView), vc.presentingViewController != nil {
            vc.dismiss(animated: true)
        } else {
            webView.removeFromSuperview()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
            completionHandler()
        })
        presentAlert(alert, on: webView, fallback: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
            completionHandler(true)
        })
        presentAlert(alert, on: webView, fallback: { completionHandler(false) })
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        presentAlert(alert, on: webView, fallback: { completionHandler(nil) })
    }

    private func presentAlert(
        _ alert: UIAlertController,
        on webView: WKWebView,
        fallback: @escaping () -> Void
    ) {
        guard let viewController = topViewController(for: webView.window) else {
            fallback()
            return
        }
        viewController.present(alert, animated: true)
    }

    private func topViewController(for window: UIWindow?) -> UIViewController? {
        guard let window = window else { return nil }
        var topVC = window.rootViewController
        while let presented = topVC?.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    private func findViewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }
}
