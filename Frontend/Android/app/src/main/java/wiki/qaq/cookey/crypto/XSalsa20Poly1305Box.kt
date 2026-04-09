package wiki.qaq.cookey.crypto

import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import com.goterl.lazysodium.interfaces.Box
import com.goterl.lazysodium.interfaces.SecretBox

object XSalsa20Poly1305Box {

    private val sodium = LazySodiumAndroid(SodiumAndroid())

    data class SealResult(
        val ephemeralPublicKey: ByteArray,
        val nonce: ByteArray,
        val ciphertext: ByteArray
    )

    fun seal(plaintext: ByteArray, recipientPublicKey: ByteArray): SealResult {
        require(recipientPublicKey.size == Box.PUBLICKEYBYTES) {
            "Invalid recipient public key size: ${recipientPublicKey.size}"
        }

        // Generate ephemeral X25519 keypair
        val ephemeralPublicKey = ByteArray(Box.PUBLICKEYBYTES)
        val ephemeralSecretKey = ByteArray(Box.SECRETKEYBYTES)
        sodium.cryptoBoxKeypair(ephemeralPublicKey, ephemeralSecretKey)

        // Generate random nonce
        val nonce = sodium.randomBytesBuf(Box.NONCEBYTES) // 24 bytes for XSalsa20

        // Encrypt: crypto_box_easy (ECDH + XSalsa20-Poly1305)
        val ciphertext = ByteArray(plaintext.size + Box.MACBYTES)
        val success = sodium.cryptoBoxEasy(
            ciphertext,
            plaintext,
            plaintext.size.toLong(),
            nonce,
            recipientPublicKey,
            ephemeralSecretKey
        )
        check(success) { "Encryption failed" }

        return SealResult(
            ephemeralPublicKey = ephemeralPublicKey,
            nonce = nonce,
            ciphertext = ciphertext
        )
    }

    fun open(
        ciphertext: ByteArray,
        nonce: ByteArray,
        ephemeralPublicKey: ByteArray,
        recipientSecretKey: ByteArray
    ): ByteArray {
        require(nonce.size == Box.NONCEBYTES) { "Invalid nonce size" }
        require(ephemeralPublicKey.size == Box.PUBLICKEYBYTES) { "Invalid public key size" }
        require(recipientSecretKey.size == Box.SECRETKEYBYTES) { "Invalid secret key size" }

        val plaintext = ByteArray(ciphertext.size - Box.MACBYTES)
        val success = sodium.cryptoBoxOpenEasy(
            plaintext,
            ciphertext,
            ciphertext.size.toLong(),
            nonce,
            ephemeralPublicKey,
            recipientSecretKey
        )
        check(success) { "Decryption failed - authentication error" }

        return plaintext
    }
}
