package wiki.qaq.cookey

import android.app.Application
import android.util.Log
import android.webkit.WebView
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import wiki.qaq.cookey.service.LogCategory
import wiki.qaq.cookey.service.LogStore
import wiki.qaq.cookey.service.AppIconSettings
import wiki.qaq.cookey.service.PushTokenStore

class CookeyApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
            LogStore.debug(this, LogCategory.BROWSER, "WebView remote debugging enabled")
        }

        AppIconSettings.synchronizeSelection(this)

        // Initialize Firebase (safe even without google-services.json for development)
        try {
            FirebaseApp.initializeApp(this)
            fetchFCMToken()
        } catch (e: Exception) {
            Log.w("CookeyApp", "Firebase initialization skipped: ${e.message}")
        }
    }

    private fun fetchFCMToken() {
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { token ->
                PushTokenStore.setToken(this, token)
                LogStore.info(this, LogCategory.PUSH, "FCM token obtained")
            }
            .addOnFailureListener { e ->
                Log.w("CookeyApp", "FCM token fetch failed: ${e.message}")
            }
    }
}
