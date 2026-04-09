package wiki.qaq.cookey.service

import android.content.Context
import androidx.core.content.edit

object PushTokenStore {

    private const val PREFS_NAME = "wiki.qaq.cookey.push"
    private const val KEY_FCM_TOKEN = "fcm_token"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getToken(context: Context): String? =
        prefs(context).getString(KEY_FCM_TOKEN, null)?.takeIf { it.isNotBlank() }

    fun setToken(context: Context, token: String?) {
        prefs(context).edit {
            if (token.isNullOrBlank()) {
                remove(KEY_FCM_TOKEN)
            } else {
                putString(KEY_FCM_TOKEN, token)
            }
        }
    }
}
