package wiki.qaq.cookey

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import wiki.qaq.cookey.ui.CookeyApp
import wiki.qaq.cookey.ui.theme.CookeyTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            CookeyTheme {
                CookeyApp(
                    initialDeepLink = intent?.data?.toString(),
                    onNewIntent = { /* updated via onNewIntent */ }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Recompose will pick up the new intent
        val uri = intent.data?.toString() ?: return
        setContent {
            CookeyTheme {
                CookeyApp(initialDeepLink = uri, onNewIntent = {})
            }
        }
    }
}
