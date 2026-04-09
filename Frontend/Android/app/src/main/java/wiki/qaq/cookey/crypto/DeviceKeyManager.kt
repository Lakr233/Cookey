package wiki.qaq.cookey.crypto

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import com.goterl.lazysodium.interfaces.Box

object DeviceKeyManager {

    private const val PREFS_NAME = "wiki.qaq.cookey.device_keys"
    private const val KEY_PUBLIC = "x25519_public"
    private const val KEY_SECRET = "x25519_secret"

    private val sodium = LazySodiumAndroid(SodiumAndroid())

    private var cachedPublicKey: ByteArray? = null
    private var cachedSecretKey: ByteArray? = null

    private fun getPrefs(context: Context) = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun loadOrCreateKeyPair(context: Context) {
        if (cachedPublicKey != null && cachedSecretKey != null) return

        val prefs = getPrefs(context)
        val pubB64 = prefs.getString(KEY_PUBLIC, null)
        val secB64 = prefs.getString(KEY_SECRET, null)

        if (pubB64 != null && secB64 != null) {
            cachedPublicKey = Base64.decode(pubB64, Base64.NO_WRAP)
            cachedSecretKey = Base64.decode(secB64, Base64.NO_WRAP)
            return
        }

        // Generate new X25519 keypair
        val publicKey = ByteArray(Box.PUBLICKEYBYTES)
        val secretKey = ByteArray(Box.SECRETKEYBYTES)
        sodium.cryptoBoxKeypair(publicKey, secretKey)

        prefs.edit()
            .putString(KEY_PUBLIC, Base64.encodeToString(publicKey, Base64.NO_WRAP))
            .putString(KEY_SECRET, Base64.encodeToString(secretKey, Base64.NO_WRAP))
            .apply()

        cachedPublicKey = publicKey
        cachedSecretKey = secretKey
    }

    fun publicKey(context: Context): ByteArray {
        loadOrCreateKeyPair(context)
        return cachedPublicKey!!
    }

    fun secretKey(context: Context): ByteArray {
        loadOrCreateKeyPair(context)
        return cachedSecretKey!!
    }

    fun publicKeyBase64(context: Context): String {
        return Base64.encodeToString(publicKey(context), Base64.NO_WRAP)
    }
}
