package wiki.qaq.cookey.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import wiki.qaq.cookey.BuildConfig
import wiki.qaq.cookey.R
import wiki.qaq.cookey.service.AppSettings

enum class SettingsSubScreen {
    NONE, TRUSTED_KEYS, LOG_VIEWER, PRIVACY_POLICY, LICENSES, WELCOME
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onShowWelcome: () -> Unit
) {
    var subScreen by remember { mutableStateOf(SettingsSubScreen.NONE) }
    val context = LocalContext.current
    var defaultServer by remember { mutableStateOf(AppSettings.getDefaultServer(context)) }
    var showServerDialog by remember { mutableStateOf(false) }

    BackHandler {
        when {
            showServerDialog -> showServerDialog = false
            subScreen != SettingsSubScreen.NONE -> subScreen = SettingsSubScreen.NONE
            else -> onBack()
        }
    }

    when (subScreen) {
        SettingsSubScreen.TRUSTED_KEYS -> {
            TrustedKeysScreen(onBack = { subScreen = SettingsSubScreen.NONE })
            return
        }
        SettingsSubScreen.LOG_VIEWER -> {
            LogViewerScreen(onBack = { subScreen = SettingsSubScreen.NONE })
            return
        }
        SettingsSubScreen.PRIVACY_POLICY -> {
            val text = remember { readRawResource(context, R.raw.privacy_policy) }
            TextViewerScreen(
                title = "Privacy Policy",
                text = text,
                onBack = { subScreen = SettingsSubScreen.NONE }
            )
            return
        }
        SettingsSubScreen.LICENSES -> {
            val text = remember { readRawResource(context, R.raw.open_source_licenses) }
            TextViewerScreen(
                title = "Open Source Licenses",
                text = text,
                onBack = { subScreen = SettingsSubScreen.NONE }
            )
            return
        }
        SettingsSubScreen.WELCOME -> {
            // Handled by parent
        }
        SettingsSubScreen.NONE -> {}
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
        ) {
            // --- General Section ---
            SectionHeader("General")

            // Default Server
            ListItem(
                headlineContent = { Text("Default Server") },
                supportingContent = {
                    Text(
                        if (defaultServer.isBlank()) "api.cookey.sh"
                        else defaultServer
                    )
                },
                leadingContent = {
                    Icon(Icons.Default.Dns, contentDescription = null)
                },
                modifier = Modifier.clickable { showServerDialog = true }
            )

            // Trusted Public Keys
            ListItem(
                headlineContent = { Text("Trusted Public Keys") },
                supportingContent = { Text("Manage trusted command-line keys") },
                leadingContent = {
                    Icon(Icons.Default.VpnKey, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, null)
                },
                modifier = Modifier.clickable { subScreen = SettingsSubScreen.TRUSTED_KEYS }
            )

            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))

            // --- Contact Us Section ---
            SectionHeader("Support")

            // View Logs
            ListItem(
                headlineContent = { Text("View Logs") },
                supportingContent = { Text("Diagnostic logs for troubleshooting") },
                leadingContent = {
                    Icon(Icons.Default.BugReport, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, null)
                },
                modifier = Modifier.clickable { subScreen = SettingsSubScreen.LOG_VIEWER }
            )

            // Submit Feedback
            ListItem(
                headlineContent = { Text("Submit Feedback") },
                leadingContent = {
                    Icon(Icons.Default.Feedback, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, null)
                },
                modifier = Modifier.clickable {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://feedback.qaq.wiki/"))
                    context.startActivity(intent)
                }
            )

            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))

            // --- About Section ---
            SectionHeader("About")

            // Guide
            ListItem(
                headlineContent = { Text("Guide") },
                supportingContent = { Text("View the welcome tutorial again") },
                leadingContent = {
                    Icon(Icons.Default.School, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, null)
                },
                modifier = Modifier.clickable { onShowWelcome() }
            )

            // Privacy Policy
            ListItem(
                headlineContent = { Text("Privacy Policy") },
                leadingContent = {
                    Icon(Icons.Default.PrivacyTip, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, null)
                },
                modifier = Modifier.clickable { subScreen = SettingsSubScreen.PRIVACY_POLICY }
            )

            // Open Source Licenses
            ListItem(
                headlineContent = { Text("Open Source Licenses") },
                leadingContent = {
                    Icon(Icons.Default.Description, contentDescription = null)
                },
                trailingContent = {
                    Icon(Icons.Default.ChevronRight, null)
                },
                modifier = Modifier.clickable { subScreen = SettingsSubScreen.LICENSES }
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Build info footer
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Cookey ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }

    if (showServerDialog) {
        ServerConfigDialog(
            currentServer = defaultServer,
            onDismiss = { showServerDialog = false },
            onSave = { server ->
                defaultServer = server
                AppSettings.setDefaultServer(context, server)
                showServerDialog = false
            },
            onReset = {
                defaultServer = ""
                AppSettings.setDefaultServer(context, "")
                showServerDialog = false
            }
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
    )
}

@Composable
private fun ServerConfigDialog(
    currentServer: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
    onReset: () -> Unit
) {
    var text by remember { mutableStateOf(currentServer) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Default Server") },
        text = {
            Column {
                Text(
                    "Enter the domain name of your Cookey relay server. HTTPS is used automatically.",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it.trim() },
                    singleLine = true,
                    placeholder = { Text("api.cookey.sh") },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(text) }) {
                Text("Save")
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onReset) {
                    Text("Reset")
                }
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
            }
        }
    )
}

fun readRawResource(context: Context, resId: Int): String {
    return context.resources.openRawResource(resId).bufferedReader().use { it.readText() }
}
