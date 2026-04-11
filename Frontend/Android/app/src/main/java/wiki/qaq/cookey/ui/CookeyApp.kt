package wiki.qaq.cookey.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import wiki.qaq.cookey.model.Phase
import wiki.qaq.cookey.ui.browser.BrowserScreen
import wiki.qaq.cookey.ui.home.HomeScreen
import wiki.qaq.cookey.ui.keyverification.KeyVerificationDialog
import wiki.qaq.cookey.ui.scanner.ScannerScreen
import wiki.qaq.cookey.ui.settings.NotificationConsentScreen
import wiki.qaq.cookey.ui.settings.SettingsScreen
import wiki.qaq.cookey.ui.upload.LoadingScreen
import wiki.qaq.cookey.ui.upload.UploadProgressScreen
import wiki.qaq.cookey.ui.welcome.WelcomeScreen

@Composable
fun CookeyApp(
    initialDeepLink: String? = null,
    onNewIntent: () -> Unit = {},
    viewModel: CookeyViewModel = viewModel()
) {
    val phase by viewModel.phase.collectAsStateWithLifecycle()
    val showKeyVerification by viewModel.showKeyVerification.collectAsStateWithLifecycle()
    val keyVerificationResult by viewModel.keyVerificationResult.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Check first launch and perform health check
    LaunchedEffect(Unit) {
        viewModel.checkFirstLaunch(context)
        viewModel.performHealthCheck(context)
    }

    LaunchedEffect(initialDeepLink) {
        if (initialDeepLink != null) {
            viewModel.handleIncomingDeepLink(context, initialDeepLink)
        }
    }

    if (showKeyVerification && keyVerificationResult != null) {
        KeyVerificationDialog(
            result = keyVerificationResult!!,
            onTrust = { viewModel.onKeyTrusted(context) },
            onReject = { viewModel.onKeyRejected() }
        )
    }

    when (val currentPhase = phase) {
        is Phase.Idle -> HomeScreen(
            onScanClick = { viewModel.startScanning() },
            onPairKeyEntered = { viewModel.handlePairKey(context, it) },
            onSettingsClick = { viewModel.showSettings() },
            onHowToUseClick = { viewModel.showWelcome() }
        )
        is Phase.Settings -> SettingsScreen(
            onBack = { viewModel.reset() },
            onShowWelcome = { viewModel.showWelcome() }
        )
        is Phase.Welcome -> WelcomeScreen(
            onFinish = { viewModel.finishWelcome(context) }
        )
        is Phase.Scanning -> ScannerScreen(
            onQrCodeScanned = { viewModel.handleDeepLink(context, it) },
            onBack = { viewModel.reset() }
        )
        is Phase.ResolvingPairKey -> LoadingScreen(
            message = "Connecting to ${currentPhase.serverHost}..."
        )
        is Phase.Validating -> LoadingScreen(
            message = "Validating request..."
        )
        is Phase.Browsing -> BrowserScreen(
            targetURL = currentPhase.deepLink.targetURL,
            seedSession = viewModel.seedSession,
            onSendSession = { cookies, origins ->
                viewModel.captureAndUpload(context, cookies, origins)
            },
            onBack = { viewModel.reset() }
        )
        is Phase.NotificationConsent -> NotificationConsentScreen(
            serverHost = currentPhase.serverHost,
            onEnable = { viewModel.onNotificationConsentEnabled(context) },
            onSkip = { viewModel.onNotificationConsentSkipped(context) }
        )
        is Phase.Uploading -> UploadProgressScreen(isUploading = true)
        is Phase.Done -> UploadProgressScreen(
            isUploading = false,
            isSuccess = true,
            onDone = { viewModel.reset() }
        )
        is Phase.Failed -> UploadProgressScreen(
            isUploading = false,
            isSuccess = false,
            errorMessage = currentPhase.message,
            onDone = { viewModel.reset() }
        )
    }
}
