package wiki.qaq.cookey.model

sealed class Phase {
    data object Idle : Phase()
    data object Scanning : Phase()
    data class ResolvingPairKey(val serverHost: String) : Phase()
    data class Validating(val deepLink: DeepLink) : Phase()
    data class Browsing(val deepLink: DeepLink) : Phase()
    data object Uploading : Phase()
    data object Done : Phase()
    data class Failed(val message: String) : Phase()
    data object Settings : Phase()
    data class Welcome(val markSeenOnFinish: Boolean) : Phase()
    data class NotificationConsent(val serverHost: String) : Phase()
}
