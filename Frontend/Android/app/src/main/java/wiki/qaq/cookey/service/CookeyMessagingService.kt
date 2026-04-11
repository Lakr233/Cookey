package wiki.qaq.cookey.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import wiki.qaq.cookey.MainActivity
import wiki.qaq.cookey.R

class CookeyMessagingService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "CookeyFCM"
        const val ACTION_OPEN_REQUEST = "wiki.qaq.cookey.OPEN_REQUEST"
        private const val CHANNEL_ID = "cookey_refresh_alerts_v2"
        private const val LEGACY_CHANNEL_ID = "cookey_refresh"
        private const val CHANNEL_NAME = "Login Requests"
        private val VIBRATION_PATTERN = longArrayOf(0, 250, 150, 250)

        fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                return
            }

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for login and session refresh requests"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = VIBRATION_PATTERN
                setSound(soundUri, audioAttributes)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New FCM token received")
        PushTokenStore.setToken(applicationContext, token)
        LogStore.info(applicationContext, LogCategory.PUSH, "FCM token refreshed")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "FCM message received: ${message.data}")
        LogStore.info(applicationContext, LogCategory.PUSH, "Push notification received")

        val pairKey = message.data["pair_key"]
        val serverUrl = message.data["server_url"]

        if (pairKey.isNullOrBlank()) {
            LogStore.error(applicationContext, LogCategory.PUSH, "Push missing pair_key")
            return
        }

        // Build cookey:// deep link
        val host = serverUrl?.let {
            try {
                Uri.parse(it).host
            } catch (_: Exception) {
                null
            }
        }

        val deepLinkUri = if (host != null) {
            "cookey://$pairKey?host=$host"
        } else {
            "cookey://$pairKey"
        }

        LogStore.info(applicationContext, LogCategory.PUSH, "Constructed deep link: $deepLinkUri")

        // Show notification that opens the deep link
        showNotification(deepLinkUri, message)
    }

    private fun showNotification(deepLinkUri: String, message: RemoteMessage) {
        ensureNotificationChannel()

        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLinkUri)).apply {
            action = ACTION_OPEN_REQUEST
            setClass(applicationContext, MainActivity::class.java)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            System.currentTimeMillis().toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Determine notification text from data or defaults
        val requestType = message.data["request_type"] ?: "refresh"
        val targetUrl = message.data["target_url"] ?: ""
        val title = message.data["title"] ?: if (requestType == "refresh") {
            "Session Refresh Request"
        } else {
            "Login Request"
        }
        val body = message.data["body"] ?: if (targetUrl.isNotBlank()) {
            "Tap to approve the request for $targetUrl"
        } else {
            "Tap to approve the request"
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(Notification.DEFAULT_ALL)
            .setVibrate(VIBRATION_PATTERN)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun ensureNotificationChannel() {
        ensureNotificationChannel(applicationContext)
    }
}
