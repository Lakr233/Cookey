package wiki.qaq.cookey.ui

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import wiki.qaq.cookey.BuildConfig
import wiki.qaq.cookey.crypto.DeviceKeyManager
import wiki.qaq.cookey.crypto.RequestAuthenticator
import wiki.qaq.cookey.crypto.XSalsa20Poly1305Box
import wiki.qaq.cookey.model.*
import wiki.qaq.cookey.network.PairKeyResolveResponse
import wiki.qaq.cookey.network.RelayClient
import wiki.qaq.cookey.network.RelayException
import wiki.qaq.cookey.model.DeviceInfo
import wiki.qaq.cookey.service.*
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

class CookeyViewModel : ViewModel() {

    companion object {
        private const val TAG = "CookeyViewModel"
    }

    private val _phase = MutableStateFlow<Phase>(Phase.Idle)
    val phase = _phase.asStateFlow()

    private val _showKeyVerification = MutableStateFlow(false)
    val showKeyVerification = _showKeyVerification.asStateFlow()

    private val _keyVerificationResult = MutableStateFlow<KeyVerificationResult?>(null)
    val keyVerificationResult = _keyVerificationResult.asStateFlow()

    var seedSession: CapturedSession? = null
        private set

    private var phaseBeforeWelcome: Phase = Phase.Idle
    private var currentDeepLink: DeepLink? = null
    private var currentClient: RelayClient? = null
    private var pendingKeyVerificationContext: Context? = null

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val healthCheck = HealthCheckModel()

    fun startScanning() {
        _phase.value = Phase.Scanning
    }

    fun reset() {
        _phase.value = Phase.Idle
        currentDeepLink = null
        currentClient = null
        seedSession = null
        _showKeyVerification.value = false
        _keyVerificationResult.value = null
    }

    fun showSettings() {
        _phase.value = Phase.Settings
    }

    fun showWelcome() {
        if (_phase.value !is Phase.Welcome) {
            phaseBeforeWelcome = _phase.value
        }
        _phase.value = Phase.Welcome(markSeenOnFinish = false)
    }

    fun checkFirstLaunch(context: Context) {
        if (!AppSettings.hasSeenWelcome(context)) {
            phaseBeforeWelcome = Phase.Idle
            _phase.value = Phase.Welcome(markSeenOnFinish = true)
        }
    }

    fun finishWelcome(context: Context) {
        val welcomePhase = _phase.value as? Phase.Welcome
        if (welcomePhase?.markSeenOnFinish == true) {
            AppSettings.setWelcomeSeenVersion(context, BuildConfig.VERSION_NAME)
        }
        _phase.value = phaseBeforeWelcome
        phaseBeforeWelcome = Phase.Idle
    }

    fun performHealthCheck(context: Context) {
        val serverURL = AppSettings.getEffectiveServer(context)
        viewModelScope.launch(Dispatchers.IO) {
            healthCheck.check(serverURL)
            val status = healthCheck.status.value
            if (status == HealthStatus.FAILED) {
                val msg = healthCheck.errorMessage.value ?: "Unknown error"
                LogStore.error(context, LogCategory.NETWORK, "Health check failed: $msg")
            } else if (status == HealthStatus.HEALTHY) {
                LogStore.debug(context, LogCategory.NETWORK, "Health check passed")
            }
        }
    }

    fun handleDeepLink(context: Context, uriString: String) {
        val pairKeyDeepLink = parsePairKeyDeepLink(uriString) ?: run {
            LogStore.error(context, LogCategory.MODEL, "Invalid deep link: $uriString")
            _phase.value = Phase.Failed("Invalid link")
            return
        }
        handlePairKey(context, pairKeyDeepLink.pairKey, pairKeyDeepLink.host)
    }

    fun handlePairKey(context: Context, pairKey: String, host: String? = null) {
        // Build initial server URL for pair key resolution.
        // If host contains "://", treat as a full URL; otherwise default to https.
        val serverBase = when {
            host == null -> AppSettings.getEffectiveServer(context)
            host.contains("://") -> host
            else -> "https://$host"
        }
        val displayHost = host?.removePrefix("http://")?.removePrefix("https://")
            ?: serverBase.removePrefix("https://").removePrefix("http://")
        _phase.value = Phase.ResolvingPairKey(displayHost)

        LogStore.info(context, LogCategory.NETWORK, "Resolving pair key on $displayHost")

        viewModelScope.launch(Dispatchers.IO) {
            try {
                val client = RelayClient(serverBase)
                currentClient = client

                val response = client.resolvePairKey(pairKey.trim())
                val serverURL = response.serverURL.ifBlank { serverBase }

                // If server_url differs from initial base, create a new client for subsequent calls
                if (serverURL != serverBase) {
                    val newClient = RelayClient(serverURL)
                    currentClient = newClient
                }

                val requestSecret = Base64.decode(response.requestSecret, Base64.URL_SAFE or Base64.NO_PADDING)

                // Verify request proof
                val proofValid = RequestAuthenticator.verifyRequestProof(
                    rid = response.rid,
                    serverURL = serverURL,
                    targetURL = response.targetURL,
                    recipientPublicKey = response.cliPublicKey,
                    deviceID = response.deviceID,
                    requestType = response.requestType,
                    expiresAt = response.expiresAt,
                    requestSecret = requestSecret,
                    expectedProof = response.requestProof
                )

                if (!proofValid) {
                    LogStore.error(context, LogCategory.CRYPTO, "Request proof verification failed for rid=${response.rid}")
                    _phase.value = Phase.Failed("Request verification failed. The request may have been tampered with.")
                    return@launch
                }

                LogStore.info(context, LogCategory.MODEL, "Pair key resolved: rid=${response.rid}, target=${response.targetURL}")

                val deepLink = DeepLink(
                    rid = response.rid,
                    serverURL = serverURL,
                    targetURL = response.targetURL,
                    recipientPublicKeyBase64 = response.cliPublicKey,
                    deviceID = response.deviceID,
                    requestType = RequestType.from(response.requestType),
                    expiresAt = response.expiresAt,
                    requestProof = response.requestProof,
                    requestSecret = response.requestSecret
                )
                currentDeepLink = deepLink

                _phase.value = Phase.Validating(deepLink)
                validateAndProceed(context, deepLink, currentClient!!)
            } catch (e: RelayException) {
                val msg = when {
                    e.isNotFound || e.isGone -> "Invalid or expired pair key."
                    else -> "Connection error: ${e.message}"
                }
                LogStore.error(context, LogCategory.NETWORK, "Pair key resolution failed: ${e.message}")
                _phase.value = Phase.Failed(msg)
            } catch (e: Exception) {
                Log.e(TAG, "Error resolving pair key", e)
                LogStore.error(context, LogCategory.NETWORK, "Pair key resolution error: ${e.message}")
                _phase.value = Phase.Failed("Connection error: ${e.message}")
            }
        }
    }

    private suspend fun validateAndProceed(context: Context, deepLink: DeepLink, client: RelayClient) {
        try {
            // Check request status
            val status = client.fetchRequestStatus(deepLink.rid)
            if (status.status == "expired") {
                LogStore.error(context, LogCategory.MODEL, "Request expired: rid=${deepLink.rid}")
                _phase.value = Phase.Failed("This request has expired.")
                return
            }

            // For refresh: load seed session
            if (deepLink.requestType == RequestType.REFRESH) {
                LogStore.info(context, LogCategory.MODEL, "Loading seed session for refresh request")
                loadSeedSession(context, deepLink, client)
            }

            // Key verification
            val verifyResult = TrustedKeyStore.verify(
                context, deepLink.deviceID, deepLink.recipientPublicKeyBase64
            )

            LogStore.info(context, LogCategory.CRYPTO, "Key verification: state=${verifyResult.state}")

            when (verifyResult.state) {
                KeyVerificationState.TRUSTED -> {
                    TrustedKeyStore.updateLastSeen(context, deepLink.deviceID)
                    _phase.value = Phase.Browsing(deepLink)
                }
                else -> {
                    pendingKeyVerificationContext = context
                    _keyVerificationResult.value = verifyResult
                    _showKeyVerification.value = true
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Validation failed", e)
            LogStore.error(context, LogCategory.MODEL, "Validation failed: ${e.message}")
            _phase.value = Phase.Failed("Validation failed: ${e.message}")
        }
    }

    private suspend fun loadSeedSession(context: Context, deepLink: DeepLink, client: RelayClient) {
        try {
            val envelope = client.fetchSeedSession(deepLink.rid) ?: return

            val secretKey = DeviceKeyManager.secretKey(context)
            val ciphertext = Base64.decode(envelope.ciphertext, Base64.DEFAULT)
            val nonce = Base64.decode(envelope.nonce, Base64.DEFAULT)
            val ephemeralPublicKey = Base64.decode(envelope.ephemeralPublicKey, Base64.DEFAULT)

            val plaintext = XSalsa20Poly1305Box.open(
                ciphertext = ciphertext,
                nonce = nonce,
                ephemeralPublicKey = ephemeralPublicKey,
                recipientSecretKey = secretKey
            )

            val payload = json.decodeFromString<SeedSessionPayload>(String(plaintext, Charsets.UTF_8))
            seedSession = CapturedSession(
                cookies = payload.cookies,
                origins = payload.origins
            )
            LogStore.info(context, LogCategory.MODEL, "Seed session loaded successfully")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load seed session (continuing without)", e)
            LogStore.error(context, LogCategory.MODEL, "Seed session load failed: ${e.message}")
        }
    }

    fun onKeyTrusted(context: Context) {
        val deepLink = currentDeepLink ?: return
        TrustedKeyStore.trust(context, deepLink.deviceID, deepLink.recipientPublicKeyBase64)
        LogStore.info(context, LogCategory.CRYPTO, "Key trusted for device=${deepLink.deviceID}")
        _showKeyVerification.value = false
        _keyVerificationResult.value = null
        _phase.value = Phase.Browsing(deepLink)
    }

    fun onKeyRejected() {
        _showKeyVerification.value = false
        _keyVerificationResult.value = null
        _phase.value = Phase.Failed("Connection rejected.")
    }

    fun captureAndUpload(
        context: Context,
        cookies: List<CapturedCookie>,
        origins: List<CapturedOrigin>
    ) {
        val deepLink = currentDeepLink ?: return
        val client = currentClient ?: return

        if (cookies.isEmpty() && origins.all { it.localStorage.isEmpty() }) {
            LogStore.error(context, LogCategory.BROWSER, "Empty session payload")
            _phase.value = Phase.Failed(UploadError.EmptySessionPayload.userMessage)
            return
        }

        _phase.value = Phase.Uploading
        LogStore.info(context, LogCategory.NETWORK, "Starting session upload for rid=${deepLink.rid}")

        viewModelScope.launch(Dispatchers.IO) {
            try {
                // Build device info with FCM token for future refresh pushes
                val deviceInfo = buildDeviceInfo(context, deepLink.deviceID)

                val session = CapturedSession(cookies = cookies, origins = origins, deviceInfo = deviceInfo)
                val plaintext = json.encodeToString(CapturedSession.serializer(), session)
                    .toByteArray(Charsets.UTF_8)

                val recipientPublicKey = try {
                    Base64.decode(deepLink.recipientPublicKeyBase64, Base64.DEFAULT)
                } catch (e: Exception) {
                    LogStore.error(context, LogCategory.CRYPTO, "Invalid recipient public key")
                    _phase.value = Phase.Failed(UploadError.InvalidRecipientPublicKey.userMessage)
                    return@launch
                }

                val sealResult = try {
                    XSalsa20Poly1305Box.seal(plaintext, recipientPublicKey)
                } catch (e: Exception) {
                    LogStore.error(context, LogCategory.CRYPTO, "Encryption failed: ${e.message}")
                    _phase.value = Phase.Failed(UploadError.InvalidSessionPayload.userMessage)
                    return@launch
                }

                val ephPubB64 = Base64.encodeToString(sealResult.ephemeralPublicKey, Base64.NO_WRAP)
                val nonceB64 = Base64.encodeToString(sealResult.nonce, Base64.NO_WRAP)
                val ciphertextB64 = Base64.encodeToString(sealResult.ciphertext, Base64.NO_WRAP)

                val capturedAt = DateTimeFormatter.ISO_INSTANT
                    .format(Instant.now().atOffset(ZoneOffset.UTC))

                val requestSecret = Base64.decode(
                    deepLink.requestSecret, Base64.URL_SAFE or Base64.NO_PADDING
                )

                val signature = RequestAuthenticator.computeEnvelopeProof(
                    rid = deepLink.rid,
                    algorithm = "x25519-xsalsa20poly1305",
                    ephemeralPublicKey = ephPubB64,
                    nonce = nonceB64,
                    ciphertext = ciphertextB64,
                    capturedAt = capturedAt,
                    version = 1,
                    requestSecret = requestSecret
                )

                val envelope = EncryptedSessionEnvelope(
                    ephemeralPublicKey = ephPubB64,
                    nonce = nonceB64,
                    ciphertext = ciphertextB64,
                    capturedAt = capturedAt,
                    requestSignature = signature
                )

                client.uploadSession(deepLink.rid, envelope)
                LogStore.info(context, LogCategory.NETWORK, "Session uploaded successfully")

                // Show notification consent if not yet prompted for this server
                if (!AppSettings.getAllowRefresh(context) &&
                    !AppSettings.hasPromptedNotification(context, deepLink.serverURL)) {
                    val host = deepLink.serverURL
                        .removePrefix("https://").removePrefix("http://")
                    _phase.value = Phase.NotificationConsent(host)
                } else {
                    _phase.value = Phase.Done
                }
            } catch (e: RelayException) {
                LogStore.error(context, LogCategory.NETWORK, "Upload server error: ${e.code} ${e.message}")
                _phase.value = Phase.Failed(UploadError.ServerError(e.code, e.message ?: "Unknown").userMessage)
            } catch (e: Exception) {
                Log.e(TAG, "Upload failed", e)
                LogStore.error(context, LogCategory.NETWORK, "Upload failed: ${e.message}")
                _phase.value = Phase.Failed(UploadError.NetworkError(e.message ?: "Unknown error").userMessage)
            }
        }
    }

    fun onNotificationConsentDone(context: Context) {
        val serverURL = currentDeepLink?.serverURL
        if (serverURL != null) {
            AppSettings.setPromptedNotification(context, serverURL)
        }
        _phase.value = Phase.Done
    }

    private fun buildDeviceInfo(context: Context, deviceID: String): DeviceInfo? {
        if (!AppSettings.getAllowRefresh(context)) return null

        val fcmToken = PushTokenStore.getToken(context) ?: return null
        val publicKeyBase64 = try {
            Base64.encodeToString(DeviceKeyManager.publicKey(context), Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }

        LogStore.debug(context, LogCategory.PUSH, "Attaching FCM device info to captured session")
        return DeviceInfo(
            deviceID = deviceID,
            fcmToken = fcmToken,
            publicKey = publicKeyBase64
        )
    }
}
