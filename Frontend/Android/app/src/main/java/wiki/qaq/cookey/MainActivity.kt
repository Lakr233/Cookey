package wiki.qaq.cookey

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import wiki.qaq.cookey.service.CookeyMessagingService
import wiki.qaq.cookey.ui.CookeyApp
import wiki.qaq.cookey.ui.theme.CookeyTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            CookeyTheme {
                CookeyApp(
                    initialDeepLink = extractDeepLink(intent),
                    onNewIntent = { /* updated via onNewIntent */ }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Recompose will pick up the new intent
        val uri = extractDeepLink(intent) ?: return
        setContent {
            CookeyTheme {
                CookeyApp(initialDeepLink = uri, onNewIntent = {})
            }
        }
    }

    private fun extractDeepLink(intent: Intent?): String? {
        val directUri = intent?.data?.toString()
        if (!directUri.isNullOrBlank()) {
            return directUri
        }

        if (intent?.action != CookeyMessagingService.ACTION_OPEN_REQUEST) {
            return null
        }

        val pairKey = intent.extras?.getString("pair_key")?.takeIf { it.isNotBlank() } ?: return null
        val serverURL = intent.extras?.getString("server_url")?.takeIf { it.isNotBlank() }

        return if (serverURL != null) {
            "cookey://$pairKey?host=${Uri.encode(serverURL)}"
        } else {
            "cookey://$pairKey"
        }
    }
}
