package wiki.qaq.cookey.service

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

object AppSettings {

    private const val PREFS_NAME = "wiki.qaq.cookey.settings"
    private const val KEY_DEFAULT_SERVER = "default_server"
    private const val KEY_ALLOW_REFRESH = "allow_refresh_requests"
    private const val KEY_APP_ICON = "app_icon"
    private const val KEY_WELCOME_SEEN_VERSION = "welcome_seen_version"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // Default server
    fun getDefaultServer(context: Context): String =
        prefs(context).getString(KEY_DEFAULT_SERVER, "") ?: ""

    fun setDefaultServer(context: Context, server: String) =
        prefs(context).edit { putString(KEY_DEFAULT_SERVER, server) }

    fun getEffectiveServer(context: Context): String {
        val custom = getDefaultServer(context)
        return if (custom.isNotBlank()) "https://$custom" else wiki.qaq.cookey.BuildConfig.DEFAULT_SERVER_ENDPOINT
    }

    // Allow refresh requests
    fun getAllowRefresh(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ALLOW_REFRESH, false)

    fun setAllowRefresh(context: Context, allow: Boolean) =
        prefs(context).edit { putBoolean(KEY_ALLOW_REFRESH, allow) }

    // App icon
    fun getAppIcon(context: Context): String =
        prefs(context).getString(KEY_APP_ICON, "") ?: ""

    fun setAppIcon(context: Context, value: String) =
        prefs(context).edit { putString(KEY_APP_ICON, value) }

    // Notification prompt state (per-server)
    fun hasPromptedNotification(context: Context, serverURL: String): Boolean =
        prefs(context).getBoolean("notification_prompted::$serverURL", false)

    fun setPromptedNotification(context: Context, serverURL: String) =
        prefs(context).edit { putBoolean("notification_prompted::$serverURL", true) }

    // Welcome/onboarding
    fun getWelcomeSeenVersion(context: Context): String? =
        prefs(context).getString(KEY_WELCOME_SEEN_VERSION, null)

    fun setWelcomeSeenVersion(context: Context, version: String) =
        prefs(context).edit { putString(KEY_WELCOME_SEEN_VERSION, version) }

    fun hasSeenWelcome(context: Context): Boolean =
        getWelcomeSeenVersion(context) != null
}
