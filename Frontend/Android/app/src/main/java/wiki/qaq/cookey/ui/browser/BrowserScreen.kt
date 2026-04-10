package wiki.qaq.cookey.ui.browser

import android.annotation.SuppressLint
import android.net.Uri
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import wiki.qaq.cookey.model.CapturedCookie
import wiki.qaq.cookey.model.CapturedOrigin
import wiki.qaq.cookey.model.CapturedSession
import wiki.qaq.cookey.model.CapturedStorageItem
import java.util.LinkedHashMap
import kotlin.coroutines.resume

// JavaScript to detect WebAuthn/Passkey requests
private const val PASSKEY_DETECTION_JS = """
(function() {
    if (window.__cookeyPasskeyDetected) return;
    window.__cookeyPasskeyDetected = true;

    var origCreate = navigator.credentials && navigator.credentials.create;
    var origGet = navigator.credentials && navigator.credentials.get;

    if (origCreate) {
        navigator.credentials.create = function(options) {
            if (options && options.publicKey) {
                window.__cookeyPasskeyRequested = true;
                if (window.CookeyBridge) window.CookeyBridge.onPasskeyDetected();
            }
            return origCreate.apply(this, arguments);
        };
    }
    if (origGet) {
        navigator.credentials.get = function(options) {
            if (options && options.publicKey) {
                window.__cookeyPasskeyRequested = true;
                if (window.CookeyBridge) window.CookeyBridge.onPasskeyDetected();
            }
            return origGet.apply(this, arguments);
        };
    }
})();
"""

private const val HISTORY_BACK_GUARD_JS = """
(function() {
    if (window.__cookeyHistoryBackGuardInstalled) return;
    window.__cookeyHistoryBackGuardInstalled = true;

    var originalBack = window.history && window.history.back ? window.history.back.bind(window.history) : null;
    var originalGo = window.history && window.history.go ? window.history.go.bind(window.history) : null;

    function canGoBack(steps) {
        try {
            return window.history.length > Math.abs(steps);
        } catch (e) {
            return false;
        }
    }

    if (originalBack) {
        window.history.back = function() {
            if (canGoBack(-1)) {
                return originalBack();
            }
        };
    }

    if (originalGo) {
        window.history.go = function(delta) {
            if (typeof delta !== 'number' || delta >= 0) {
                return originalGo(delta);
            }
            if (canGoBack(delta)) {
                return originalGo(delta);
            }
        };
    }
})();
"""

@OptIn(ExperimentalMaterial3Api::class)
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun BrowserScreen(
    targetURL: String,
    seedSession: CapturedSession?,
    userAgent: String,
    onSendSession: (List<CapturedCookie>, List<CapturedOrigin>) -> Unit,
    onBack: () -> Unit
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var pageTitle by remember { mutableStateOf("Browser") }
    var showSendDialog by remember { mutableStateOf(false) }
    var showPasskeyAlert by remember { mutableStateOf(false) }
    val visitedUrls = remember { mutableStateListOf<String>() }
    val scope = rememberCoroutineScope()
    val handleBackNavigation = {
        val currentWebView = webView
        if (currentWebView?.canGoBack() == true) {
            currentWebView.goBack()
        } else {
            onBack()
        }
    }

    BackHandler(onBack = handleBackNavigation)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(pageTitle, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { showSendDialog = true }) {
                        Icon(Icons.AutoMirrored.Filled.Send, "Send Session")
                    }
                }
            )
        }
    ) { padding ->
        AndroidView(
            factory = { context ->
                WebView(context).apply {
                    settings.apply {
                        javaScriptEnabled = true
                        domStorageEnabled = true
                        userAgentString = settings.userAgentString.replace(
                            Regex("\\bChrome/[\\S]+"),
                            userAgent
                        )
                        setSupportMultipleWindows(true)
                        javaScriptCanOpenWindowsAutomatically = true
                    }

                    // Add JavaScript bridge for passkey detection
                    addJavascriptInterface(object {
                        @JavascriptInterface
                        fun onPasskeyDetected() {
                            showPasskeyAlert = true
                        }
                    }, "CookeyBridge")

                    // Use non-persistent cookie store equivalent:
                    // Clear cookies before loading
                    CookieManager.getInstance().removeAllCookies(null)

                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView?, url: String?) {
                            super.onPageFinished(view, url)
                            pageTitle = view?.title ?: "Browser"
                            recordVisitedUrl(url ?: view?.url?.toString(), visitedUrls)
                            // Inject passkey detection script
                            view?.evaluateJavascript(PASSKEY_DETECTION_JS, null)
                            // Keep in-page JavaScript back navigation inside WebView history.
                            view?.evaluateJavascript(HISTORY_BACK_GUARD_JS, null)
                        }

                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean {
                            // Keep all navigation in-app (prevent app switching for OAuth)
                            return false
                        }
                    }

                    webChromeClient = object : WebChromeClient() {
                        override fun onCreateWindow(
                            view: WebView?,
                            isDialog: Boolean,
                            isUserGesture: Boolean,
                            resultMsg: android.os.Message?
                        ): Boolean {
                            // Handle window.open() for OAuth popups
                            val transport = resultMsg?.obj as? WebView.WebViewTransport
                            val newWebView = WebView(context).apply {
                                settings.javaScriptEnabled = true
                                settings.domStorageEnabled = true
                            }
                            transport?.webView = newWebView
                            resultMsg?.sendToTarget()
                            // Load popup content in the main webview
                            newWebView.webViewClient = object : WebViewClient() {
                                override fun shouldOverrideUrlLoading(
                                    view: WebView?,
                                    request: WebResourceRequest?
                                ): Boolean {
                                    view?.loadUrl(request?.url.toString())
                                    return true
                                }
                            }
                            return true
                        }

                        override fun onJsAlert(
                            view: WebView?, url: String?, message: String?,
                            result: JsResult?
                        ): Boolean {
                            return false // Use default handling
                        }
                    }

                    // Pre-populate seed session cookies if present
                    if (seedSession != null) {
                        val cookieManager = CookieManager.getInstance()
                        for (cookie in seedSession.cookies) {
                            val cookieString = buildString {
                                append("${cookie.name}=${cookie.value}")
                                append("; domain=${cookie.domain}")
                                append("; path=${cookie.path}")
                                if (cookie.secure) append("; secure")
                                if (cookie.httpOnly) append("; httponly")
                                if (cookie.expires > 0) {
                                    append("; max-age=${(cookie.expires - System.currentTimeMillis() / 1000).toLong()}")
                                }
                            }
                            val url = "https://${cookie.domain.removePrefix(".")}"
                            cookieManager.setCookie(url, cookieString)
                        }
                        cookieManager.flush()
                    }

                    // Inject localStorage for seed session
                    if (seedSession != null && seedSession.origins.isNotEmpty()) {
                        val jsSetup = seedSession.origins.joinToString("\n") { origin ->
                            origin.localStorage.joinToString("\n") { item ->
                                val escapedKey = item.name.replace("'", "\\'")
                                val escapedValue = item.value.replace("'", "\\'")
                                "localStorage.setItem('$escapedKey', '$escapedValue');"
                            }
                        }
                        evaluateJavascript(jsSetup, null)
                    }

                    loadUrl(targetURL)
                    webView = this
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        )
    }

    if (showSendDialog) {
        AlertDialog(
            onDismissRequest = { showSendDialog = false },
            title = { Text("Send Session") },
            text = {
                Text("This will package and send the current session state to the requester. Please confirm you have completed login or the required actions.")
            },
            confirmButton = {
                TextButton(onClick = {
                    showSendDialog = false
                    scope.launch {
                        val wv = webView ?: return@launch
                        val (cookies, origins) = captureSession(
                            webView = wv,
                            targetURL = targetURL,
                            visitedUrls = visitedUrls.toList()
                        )
                        onSendSession(cookies, origins)
                    }
                }) {
                    Text("Send")
                }
            },
            dismissButton = {
                TextButton(onClick = { showSendDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showPasskeyAlert) {
        AlertDialog(
            onDismissRequest = { showPasskeyAlert = false },
            title = { Text("Passkey Not Supported") },
            text = {
                Text("This website is requesting Passkey authentication, which is not supported in the in-app browser. Please use an alternative login method such as password or SMS verification.")
            },
            confirmButton = {
                TextButton(onClick = { showPasskeyAlert = false }) {
                    Text("OK")
                }
            }
        )
    }
}

private suspend fun captureSession(
    webView: WebView,
    targetURL: String,
    visitedUrls: List<String>
): Pair<List<CapturedCookie>, List<CapturedOrigin>> {
    val cookies = captureCookies(
        targetURL = targetURL,
        currentURL = webView.url,
        visitedUrls = visitedUrls
    )
    val origins = captureLocalStorage(webView)
    return cookies to origins
}

private fun captureCookies(
    targetURL: String,
    currentURL: String?,
    visitedUrls: List<String>
): List<CapturedCookie> {
    val cookieManager = CookieManager.getInstance()
    val candidates = buildList {
        add(targetURL)
        currentURL?.let(::add)
        addAll(visitedUrls)
    }.mapNotNull(::normalizeCookieLookupURL)
        .distinct()

    if (candidates.isEmpty()) return emptyList()

    val cookies = LinkedHashMap<String, CapturedCookie>()

    for (candidate in candidates) {
        val uri = Uri.parse(candidate)
        val domain = uri.host ?: continue
        val cookieString = cookieManager.getCookie(candidate) ?: continue

        cookieString.split(";").forEach { raw ->
            val trimmed = raw.trim()
            val eqIdx = trimmed.indexOf('=')
            if (eqIdx < 0) return@forEach

            val name = trimmed.substring(0, eqIdx).trim()
            val value = trimmed.substring(eqIdx + 1).trim()
            val cookie = CapturedCookie(
                name = name,
                value = value,
                domain = ".$domain",
                path = "/",
                expires = -1.0,
                httpOnly = false,
                secure = uri.scheme == "https",
                sameSite = "Lax"
            )
            cookies["${cookie.name}|${cookie.domain}|${cookie.path}"] = cookie
        }
    }

    return cookies.values.toList()
}

private suspend fun captureLocalStorage(
    webView: WebView
): List<CapturedOrigin> {
    val js = """
        (function() {
            try {
                var items = [];
                for (var i = 0; i < window.localStorage.length; i++) {
                    var key = window.localStorage.key(i);
                    items.push({name: key, value: window.localStorage.getItem(key) || ""});
                }
                return JSON.stringify(items);
            } catch(e) {
                return "[]";
            }
        })();
    """.trimIndent()

    val result = withContext(Dispatchers.Main) {
        suspendCancellableCoroutine<String> { continuation ->
            webView.evaluateJavascript(js) { value ->
                // evaluateJavascript wraps the result in quotes and escapes
                val unquoted = if (value.startsWith("\"") && value.endsWith("\"")) {
                    value.substring(1, value.length - 1)
                        .replace("\\\"", "\"")
                        .replace("\\\\", "\\")
                } else {
                    value
                }
                continuation.resume(unquoted)
            }
        }
    }

    val items = try {
        Json.decodeFromString<List<CapturedStorageItem>>(result)
    } catch (_: Exception) {
        emptyList()
    }

    val currentURL = webView.url ?: return emptyList()
    val currentUri = Uri.parse(currentURL)
    val origin = buildString {
        append(currentUri.scheme ?: "https")
        append("://")
        append(currentUri.host ?: return emptyList())
        val port = currentUri.port
        val includePort = port != -1 &&
            !((currentUri.scheme == "https" && port == 443) || (currentUri.scheme == "http" && port == 80))
        if (includePort) {
            append(":")
            append(port)
        }
    }

    return if (items.isNotEmpty()) {
        listOf(CapturedOrigin(origin = origin, localStorage = items))
    } else {
        emptyList()
    }
}

private fun recordVisitedUrl(url: String?, visitedUrls: MutableList<String>) {
    val normalized = normalizeCookieLookupURL(url) ?: return
    if (normalized !in visitedUrls) {
        visitedUrls.add(normalized)
    }
}

private fun normalizeCookieLookupURL(raw: String?): String? {
    val value = raw?.trim().orEmpty()
    if (value.isEmpty()) return null
    val uri = Uri.parse(value)
    val scheme = uri.scheme ?: return null
    val host = uri.host ?: return null
    return buildString {
        append(scheme)
        append("://")
        append(host)
        if (uri.port != -1) {
            append(":")
            append(uri.port)
        }
        append(uri.path ?: "/")
        if (uri.query != null) {
            append("?")
            append(uri.query)
        }
    }
}
