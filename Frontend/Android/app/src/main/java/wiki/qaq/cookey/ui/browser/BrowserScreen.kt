package wiki.qaq.cookey.ui.browser

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.view.ViewGroup
import android.webkit.*
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.viewinterop.AndroidView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import wiki.qaq.cookey.model.CapturedCookie
import wiki.qaq.cookey.model.CapturedOrigin
import wiki.qaq.cookey.model.CapturedSession
import wiki.qaq.cookey.model.CapturedStorageItem
import wiki.qaq.cookey.service.LogCategory
import wiki.qaq.cookey.service.LogStore
import java.util.LinkedHashMap
import kotlin.coroutines.resume

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
    onSendSession: (List<CapturedCookie>, List<CapturedOrigin>) -> Unit,
    onBack: () -> Unit
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    var isRefreshing by remember { mutableStateOf(false) }
    var pageTitle by remember { mutableStateOf("Browser") }
    var pageDomain by remember(targetURL) { mutableStateOf(extractPageDomain(targetURL)) }
    var popupWebView by remember { mutableStateOf<WebView?>(null) }
    var popupPageTitle by remember { mutableStateOf("Browser") }
    var popupPageDomain by remember { mutableStateOf("") }
    var showSendDialog by remember { mutableStateOf(false) }
    val visitedUrls = remember { mutableStateListOf<String>() }
    val scope = rememberCoroutineScope()
    val popupSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    fun updateMainPageState(title: String, domain: String) {
        pageTitle = title
        pageDomain = domain
    }

    fun updatePopupPageState(title: String, domain: String) {
        popupPageTitle = title
        popupPageDomain = domain
    }

    fun closePopup() {
        val currentPopupWebView = popupWebView ?: return
        popupWebView = null
        popupPageTitle = "Browser"
        popupPageDomain = ""
        disposeWebView(currentPopupWebView)
    }

    fun configureBrowserWebView(
        candidate: WebView,
        setRefreshing: (Boolean) -> Unit,
        updatePageState: (String, String) -> Unit,
        onPopupCreated: (WebView, String) -> Unit
    ) {
        candidate.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            setSupportMultipleWindows(true)
            javaScriptCanOpenWindowsAutomatically = true
        }

        candidate.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                super.onPageStarted(view, url, favicon)
                LogStore.info(
                    candidate.context,
                    LogCategory.BROWSER,
                    "page_started url=${url.orEmpty()}"
                )
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                setRefreshing(false)
                updatePageState(view?.title ?: "Browser", extractPageDomain(url ?: view?.url?.toString()))
                recordVisitedUrl(url ?: view?.url?.toString(), visitedUrls)
                LogStore.info(
                    candidate.context,
                    LogCategory.BROWSER,
                    "page_finished title=${view?.title.orEmpty()} url=${url ?: view?.url.orEmpty()}"
                )
                view?.evaluateJavascript(HISTORY_BACK_GUARD_JS, null)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                return false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                if (request == null || request.isForMainFrame) {
                    setRefreshing(false)
                }
                LogStore.error(
                    candidate.context,
                    LogCategory.BROWSER,
                    "resource_error url=${request?.url} code=${error?.errorCode} desc=${error?.description}"
                )
            }

            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?
            ) {
                super.onReceivedHttpError(view, request, errorResponse)
                if (request?.isForMainFrame == true) {
                    setRefreshing(false)
                }
                LogStore.error(
                    candidate.context,
                    LogCategory.BROWSER,
                    "http_error url=${request?.url} status=${errorResponse?.statusCode} reason=${errorResponse?.reasonPhrase.orEmpty()}"
                )
            }
        }

        candidate.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                LogStore.debug(
                    candidate.context,
                    LogCategory.BROWSER,
                    "console level=${consoleMessage.messageLevel()} source=${consoleMessage.sourceId()}:${consoleMessage.lineNumber()} message=${consoleMessage.message()}"
                )
                return true
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?
            ): Boolean {
                val requestedUrl = view?.hitTestResult?.extra?.takeIf { it.isNotBlank() }
                val isNestedPopupRequest = view != null && view == popupWebView
                LogStore.debug(
                    candidate.context,
                    LogCategory.BROWSER,
                    "create_window isDialog=$isDialog isUserGesture=$isUserGesture requestedUrl=${requestedUrl.orEmpty()} nested=$isNestedPopupRequest"
                )

                // A popup should never spawn another popup. Keep follow-up window.open calls
                // inside the existing popup instead of creating a nested drawer.
                if (isNestedPopupRequest) {
                    if (requestedUrl != null) {
                        view.loadUrl(requestedUrl)
                    }
                    return false
                }

                // Regular target=_blank link clicks should stay in the current webview.
                // Reserve a separate popup webview for real window.open / OAuth flows that
                // need window.opener to remain intact.
                if (isUserGesture && !isDialog && requestedUrl != null) {
                    view.loadUrl(requestedUrl)
                    return false
                }

                val popup = WebView(candidate.context)
                configureBrowserWebView(
                    candidate = popup,
                    setRefreshing = {},
                    updatePageState = ::updatePopupPageState,
                    onPopupCreated = onPopupCreated
                )

                val initialDomain = extractPageDomain(view?.hitTestResult?.extra)
                updatePopupPageState("Browser", initialDomain)
                onPopupCreated(popup, initialDomain)

                val transport = resultMsg?.obj as? WebView.WebViewTransport
                transport?.webView = popup
                resultMsg?.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView?) {
                LogStore.debug(
                    candidate.context,
                    LogCategory.BROWSER,
                    "close_window url=${window?.url.orEmpty()}"
                )
                if (window != null && window == popupWebView) {
                    closePopup()
                } else if (window != null) {
                    disposeWebView(window)
                }
            }

            override fun onJsAlert(
                view: WebView?,
                url: String?,
                message: String?,
                result: JsResult?
            ): Boolean {
                return false
            }
        }
    }

    fun handleBackNavigation() {
        val currentPopupWebView = popupWebView
        when {
            currentPopupWebView?.canGoBack() == true -> currentPopupWebView.goBack()
            currentPopupWebView != null -> closePopup()
            webView?.canGoBack() == true -> webView?.goBack()
            else -> onBack()
        }
    }

    BackHandler(onBack = ::handleBackNavigation)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            text = pageTitle,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (pageDomain.isNotEmpty()) {
                            Text(
                                text = pageDomain,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = ::handleBackNavigation) {
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
                val candidate = WebView(context).apply {
                    configureBrowserWebView(
                        candidate = this,
                        setRefreshing = { isRefreshing = it },
                        updatePageState = ::updateMainPageState,
                        onPopupCreated = { popup, _ ->
                            popupWebView?.let(::disposeWebView)
                            popupWebView = popup
                        }
                    )

                    CookieManager.getInstance().removeAllCookies(null)

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
                }
                webView = candidate
                createSwipeRefreshContainer(
                    context = context,
                    webView = candidate,
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        candidate.reload()
                    }
                )
            },
            update = { container ->
                container.isRefreshing = isRefreshing
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        )
    }

    if (popupWebView != null) {
        ModalBottomSheet(
            onDismissRequest = ::closePopup,
            sheetState = popupSheetState,
            dragHandle = null,
            contentWindowInsets = { WindowInsets(0, 0, 0, 0) }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.92f)
            ) {
                TopAppBar(
                    title = {
                        Column {
                            Text(
                                text = popupPageTitle,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (popupPageDomain.isNotEmpty()) {
                                Text(
                                    text = popupPageDomain,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    },
                    actions = {
                        IconButton(onClick = ::closePopup) {
                            Icon(Icons.Filled.Close, "Close")
                        }
                    }
                )

                key(popupWebView) {
                    AndroidView(
                        factory = { popupWebView ?: error("Popup WebView missing") },
                        modifier = Modifier
                            .fillMaxSize()
                    )
                }
            }
        }
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

private fun extractPageDomain(raw: String?): String {
    val value = raw?.trim().orEmpty()
    if (value.isEmpty()) return ""
    return runCatching {
        Uri.parse(value).host.orEmpty()
    }.getOrDefault("")
}

private fun createSwipeRefreshContainer(
    context: Context,
    webView: WebView,
    isRefreshing: Boolean,
    onRefresh: () -> Unit
): SwipeRefreshLayout {
    (webView.parent as? ViewGroup)?.removeView(webView)
    return SwipeRefreshLayout(context).apply {
        setOnChildScrollUpCallback { _, _ ->
            webView.canScrollVertically(-1)
        }
        setOnRefreshListener(onRefresh)
        this.isRefreshing = isRefreshing
        addView(
            webView,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
    }
}

private fun disposeWebView(webView: WebView) {
    (webView.parent as? ViewGroup)?.removeView(webView)
    webView.stopLoading()
    webView.webChromeClient = null
    webView.destroy()
}
