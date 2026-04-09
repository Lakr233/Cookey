package wiki.qaq.cookey.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import wiki.qaq.cookey.model.EncryptedSessionEnvelope
import java.util.concurrent.TimeUnit

@Serializable
data class PairKeyResolveResponse(
    val rid: String,
    @SerialName("server_url")
    val serverURL: String,
    @SerialName("target_url")
    val targetURL: String,
    @SerialName("cli_public_key")
    val cliPublicKey: String,
    @SerialName("device_id")
    val deviceID: String,
    @SerialName("expires_at")
    val expiresAt: String,
    @SerialName("request_proof")
    val requestProof: String,
    @SerialName("request_secret")
    val requestSecret: String,
    @SerialName("request_type")
    val requestType: String = "login"
)

@Serializable
data class RequestStatusResponse(
    val rid: String,
    val status: String,
    @SerialName("target_url")
    val targetURL: String,
    @SerialName("created_at")
    val createdAt: String,
    @SerialName("expires_at")
    val expiresAt: String,
    @SerialName("pair_key")
    val pairKey: String,
    @SerialName("request_type")
    val requestType: String = "login"
)

@Serializable
data class SessionUploadResponse(
    val rid: String,
    val status: String
)

class RelayClient(private val baseURL: String) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    suspend fun resolvePairKey(pairKey: String): PairKeyResolveResponse {
        val request = Request.Builder()
            .url("$baseURL/v1/pair/$pairKey")
            .get()
            .build()

        return executeAndDecode(request)
    }

    suspend fun fetchRequestStatus(rid: String): RequestStatusResponse {
        val request = Request.Builder()
            .url("$baseURL/v1/requests/$rid")
            .get()
            .build()

        return executeAndDecode(request)
    }

    suspend fun fetchSeedSession(rid: String): EncryptedSessionEnvelope? {
        val request = Request.Builder()
            .url("$baseURL/v1/requests/$rid/seed-session")
            .get()
            .build()

        val response = client.newCall(request).execute()
        if (response.code == 404) return null

        val body = response.body?.string() ?: throw RelayException(response.code, "Empty response")
        if (!response.isSuccessful) throw RelayException(response.code, body)

        return json.decodeFromString<EncryptedSessionEnvelope>(body)
    }

    suspend fun uploadSession(rid: String, envelope: EncryptedSessionEnvelope) {
        val jsonBody = json.encodeToString(EncryptedSessionEnvelope.serializer(), envelope)
        val request = Request.Builder()
            .url("$baseURL/v1/requests/$rid/session")
            .post(jsonBody.toRequestBody(jsonMediaType))
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: ""
        if (!response.isSuccessful) {
            throw RelayException(response.code, body)
        }
    }

    suspend fun healthCheck(): Boolean {
        return try {
            val request = Request.Builder()
                .url("$baseURL/health")
                .get()
                .build()
            val response = client.newCall(request).execute()
            response.isSuccessful
        } catch (_: Exception) {
            false
        }
    }

    private inline fun <reified T> executeAndDecode(request: Request): T {
        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: throw RelayException(response.code, "Empty response")

        if (!response.isSuccessful) {
            throw RelayException(response.code, body)
        }

        return json.decodeFromString<T>(body)
    }
}

class RelayException(val code: Int, message: String) : Exception("HTTP $code: $message") {
    val isNotFound get() = code == 404
    val isGone get() = code == 410
    val isConflict get() = code == 409
}
