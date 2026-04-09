package wiki.qaq.cookey.crypto

import android.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object RequestAuthenticator {

    fun computeRequestProof(
        rid: String,
        serverURL: String,
        targetURL: String,
        recipientPublicKey: String,
        deviceID: String,
        requestType: String,
        expiresAt: String,
        requestSecret: ByteArray
    ): String {
        val message = listOf(
            "cookey-request-v1",
            rid,
            serverURL,
            targetURL,
            recipientPublicKey,
            deviceID,
            requestType,
            expiresAt
        ).joinToString("\n")
        return hmacSha256Base64Url(requestSecret, message.toByteArray(Charsets.UTF_8))
    }

    fun verifyRequestProof(
        rid: String,
        serverURL: String,
        targetURL: String,
        recipientPublicKey: String,
        deviceID: String,
        requestType: String,
        expiresAt: String,
        requestSecret: ByteArray,
        expectedProof: String
    ): Boolean {
        val computed = computeRequestProof(
            rid, serverURL, targetURL, recipientPublicKey,
            deviceID, requestType, expiresAt, requestSecret
        )
        return computed == expectedProof
    }

    fun computeEnvelopeProof(
        rid: String,
        algorithm: String,
        ephemeralPublicKey: String,
        nonce: String,
        ciphertext: String,
        capturedAt: String,
        version: Int,
        requestSecret: ByteArray
    ): String {
        val message = listOf(
            "cookey-session-v1",
            rid,
            algorithm,
            ephemeralPublicKey,
            nonce,
            ciphertext,
            capturedAt,
            version.toString()
        ).joinToString("\n")
        return hmacSha256Base64Url(requestSecret, message.toByteArray(Charsets.UTF_8))
    }

    private fun hmacSha256Base64Url(key: ByteArray, data: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val result = mac.doFinal(data)
        return Base64.encodeToString(result, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
