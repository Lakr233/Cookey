package wiki.qaq.cookey.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CapturedSession(
    val cookies: List<CapturedCookie>,
    val origins: List<CapturedOrigin>,
    @SerialName("device_info")
    val deviceInfo: DeviceInfo? = null
)

@Serializable
data class CapturedCookie(
    val name: String,
    val value: String,
    val domain: String,
    val path: String,
    val expires: Double,
    @SerialName("httpOnly")
    val httpOnly: Boolean,
    val secure: Boolean,
    @SerialName("sameSite")
    val sameSite: String
)

@Serializable
data class CapturedOrigin(
    val origin: String,
    @SerialName("localStorage")
    val localStorage: List<CapturedStorageItem>
)

@Serializable
data class CapturedStorageItem(
    val name: String,
    val value: String
)

@Serializable
data class DeviceInfo(
    @SerialName("device_id")
    val deviceID: String,
    @SerialName("apn_token")
    val apnToken: String? = null,
    @SerialName("apn_environment")
    val apnEnvironment: String? = null,
    @SerialName("fcm_token")
    val fcmToken: String? = null,
    @SerialName("public_key")
    val publicKey: String? = null
)

@Serializable
data class SeedSessionPayload(
    val cookies: List<CapturedCookie>,
    val origins: List<CapturedOrigin>,
    @SerialName("_cookey_request")
    val request: SeedRequestPayload? = null
)

@Serializable
data class SeedRequestPayload(
    val rid: String,
    @SerialName("server_url")
    val serverURL: String,
    @SerialName("target_url")
    val targetURL: String,
    @SerialName("cli_public_key")
    val cliPublicKey: String,
    @SerialName("device_id")
    val deviceID: String,
    @SerialName("request_type")
    val requestType: String,
    @SerialName("expires_at")
    val expiresAt: String,
    @SerialName("request_proof")
    val requestProof: String,
    @SerialName("request_secret")
    val requestSecret: String
)
