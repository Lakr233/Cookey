package wiki.qaq.cookey.service

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import wiki.qaq.cookey.crypto.KeyFingerprint
import java.io.File

@Serializable
data class TrustedKey(
    @SerialName("device_id")
    val deviceID: String,
    @SerialName("public_key_base64")
    val publicKeyBase64: String,
    val fingerprint: String,
    @SerialName("first_trusted_at")
    val firstTrustedAt: String,
    @SerialName("last_seen_at")
    var lastSeenAt: String,
    var label: String? = null
)

enum class KeyVerificationState {
    TRUSTED,
    KEY_CHANGED,
    KNOWN_KEY_NEW_DEVICE,
    FIRST_TIME
}

data class KeyVerificationResult(
    val state: KeyVerificationState,
    val fingerprint: String,
    val oldFingerprint: String? = null
)

object TrustedKeyStore {

    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }
    private val lock = Any()

    private fun storeFile(context: Context): File {
        val dir = File(context.filesDir, "wiki.qaq.cookey.app")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, "trusted_clis.json")
        file.setReadable(true, true)
        file.setWritable(true, true)
        return file
    }

    private fun loadKeys(context: Context): MutableList<TrustedKey> {
        val file = storeFile(context)
        if (!file.exists()) return mutableListOf()
        return try {
            json.decodeFromString<MutableList<TrustedKey>>(file.readText())
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun saveKeys(context: Context, keys: List<TrustedKey>) {
        val file = storeFile(context)
        file.writeText(json.encodeToString(keys))
    }

    fun verify(
        context: Context,
        deviceID: String,
        publicKeyBase64: String
    ): KeyVerificationResult {
        val fingerprint = KeyFingerprint.compute(publicKeyBase64)
        synchronized(lock) {
            val keys = loadKeys(context)

            // Exact match: same device, same key
            val exactMatch = keys.find { it.deviceID == deviceID && it.publicKeyBase64 == publicKeyBase64 }
            if (exactMatch != null) {
                return KeyVerificationResult(KeyVerificationState.TRUSTED, fingerprint)
            }

            // Same device, different key
            val sameDevice = keys.find { it.deviceID == deviceID }
            if (sameDevice != null) {
                return KeyVerificationResult(
                    KeyVerificationState.KEY_CHANGED,
                    fingerprint,
                    oldFingerprint = sameDevice.fingerprint
                )
            }

            // Same key, different device
            val sameKey = keys.find { it.publicKeyBase64 == publicKeyBase64 }
            if (sameKey != null) {
                return KeyVerificationResult(KeyVerificationState.KNOWN_KEY_NEW_DEVICE, fingerprint)
            }

            // Brand new
            return KeyVerificationResult(KeyVerificationState.FIRST_TIME, fingerprint)
        }
    }

    fun trust(context: Context, deviceID: String, publicKeyBase64: String) {
        val fingerprint = KeyFingerprint.compute(publicKeyBase64)
        val now = java.time.Instant.now().toString()
        synchronized(lock) {
            val keys = loadKeys(context)

            // Remove old entry for same device if exists
            keys.removeAll { it.deviceID == deviceID }

            keys.add(
                TrustedKey(
                    deviceID = deviceID,
                    publicKeyBase64 = publicKeyBase64,
                    fingerprint = fingerprint,
                    firstTrustedAt = now,
                    lastSeenAt = now
                )
            )
            saveKeys(context, keys)
        }
    }

    fun updateLastSeen(context: Context, deviceID: String) {
        val now = java.time.Instant.now().toString()
        synchronized(lock) {
            val keys = loadKeys(context)
            keys.find { it.deviceID == deviceID }?.lastSeenAt = now
            saveKeys(context, keys)
        }
    }

    fun allKeys(context: Context): List<TrustedKey> {
        synchronized(lock) {
            return loadKeys(context)
        }
    }

    fun removeKey(context: Context, deviceID: String) {
        synchronized(lock) {
            val keys = loadKeys(context)
            keys.removeAll { it.deviceID == deviceID }
            saveKeys(context, keys)
        }
    }
}
