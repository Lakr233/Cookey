package wiki.qaq.cookey.model

import android.net.Uri

/**
 * Pair key deep link: cookey://SM8ND67N?host=api.cookey.sh
 */
data class PairKeyDeepLink(
    val pairKey: String,
    val host: String?
)

/**
 * Full authenticated request deep link, resolved from pair key via relay.
 */
data class DeepLink(
    val rid: String,
    val serverURL: String,
    val targetURL: String,
    val recipientPublicKeyBase64: String,
    val deviceID: String,
    val requestType: RequestType,
    val expiresAt: String,
    val requestProof: String,
    val requestSecret: String
)

enum class RequestType {
    LOGIN, REFRESH;

    companion object {
        fun from(value: String): RequestType = when (value.lowercase()) {
            "refresh" -> REFRESH
            else -> LOGIN
        }
    }

    fun toApiValue(): String = when (this) {
        LOGIN -> "login"
        REFRESH -> "refresh"
    }
}

fun parsePairKeyDeepLink(uriString: String): PairKeyDeepLink? {
    val uri = try { Uri.parse(uriString) } catch (_: Exception) { return null }
    if (uri.scheme?.lowercase() != "cookey") return null
    val pairKey = uri.host?.takeIf { it.isNotBlank() } ?: return null
    val host = uri.getQueryParameter("host")?.takeIf { it.isNotBlank() }
    return PairKeyDeepLink(pairKey = pairKey, host = host)
}
