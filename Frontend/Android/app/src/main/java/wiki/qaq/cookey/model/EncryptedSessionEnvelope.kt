package wiki.qaq.cookey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class EncryptedSessionEnvelope(
    val version: Int = 1,
    val algorithm: String = "x25519-xsalsa20poly1305",
    @SerialName("ephemeral_public_key")
    val ephemeralPublicKey: String,
    val nonce: String,
    val ciphertext: String,
    @SerialName("captured_at")
    val capturedAt: String,
    @SerialName("request_signature")
    val requestSignature: String? = null
)
