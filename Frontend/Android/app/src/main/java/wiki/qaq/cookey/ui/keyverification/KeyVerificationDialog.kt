package wiki.qaq.cookey.ui.keyverification

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.ShieldMoon
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import wiki.qaq.cookey.service.KeyVerificationResult
import wiki.qaq.cookey.service.KeyVerificationState

@Composable
fun KeyVerificationDialog(
    result: KeyVerificationResult,
    onTrust: () -> Unit,
    onReject: () -> Unit
) {
    Dialog(
        onDismissRequest = onReject,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            shape = MaterialTheme.shapes.extraLarge,
            tonalElevation = 6.dp
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Icon
                val (icon, iconTint) = when (result.state) {
                    KeyVerificationState.KEY_CHANGED -> Icons.Default.ShieldMoon to MaterialTheme.colorScheme.error
                    KeyVerificationState.KNOWN_KEY_NEW_DEVICE -> Icons.Default.SyncAlt to MaterialTheme.colorScheme.primary
                    else -> Icons.Default.Computer to MaterialTheme.colorScheme.primary
                }

                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = iconTint
                )

                Spacer(modifier = Modifier.height(16.dp))

                // Title
                val title = when (result.state) {
                    KeyVerificationState.FIRST_TIME -> "New Key"
                    KeyVerificationState.KEY_CHANGED -> "Security Warning"
                    KeyVerificationState.KNOWN_KEY_NEW_DEVICE -> "Known Key, New Device"
                    KeyVerificationState.TRUSTED -> "Trusted"
                }
                Text(
                    text = title,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Description
                val description = when (result.state) {
                    KeyVerificationState.FIRST_TIME ->
                        "First connection from this computer. Verify the fingerprint below matches what your terminal shows. If they don\u2019t match, reject the connection \u2014 it may be intercepted by a third party."
                    KeyVerificationState.KEY_CHANGED ->
                        "The identity of this computer has changed since you last connected. This could indicate a security issue, or the command-line tool may have been reinstalled."
                    KeyVerificationState.KNOWN_KEY_NEW_DEVICE ->
                        "This key was previously trusted under a different device identifier. This may indicate the command-line tool was migrated or reinstalled."
                    KeyVerificationState.TRUSTED -> ""
                }
                if (description.isNotEmpty()) {
                    Text(
                        text = description,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Spacer(modifier = Modifier.height(20.dp))

                // Old fingerprint (for KEY_CHANGED)
                if (result.state == KeyVerificationState.KEY_CHANGED && result.oldFingerprint != null) {
                    Text(
                        "Previous fingerprint",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    FingerprintCard(
                        fingerprint = result.oldFingerprint,
                        dimmed = true
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "New fingerprint",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                }

                // Main fingerprint card
                FingerprintCard(fingerprint = result.fingerprint)

                Spacer(modifier = Modifier.height(24.dp))

                // Trust button
                val trustText = when (result.state) {
                    KeyVerificationState.KEY_CHANGED -> "Trust New Key"
                    else -> "Trust"
                }
                Button(
                    onClick = onTrust,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(trustText)
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Reject button
                TextButton(
                    onClick = onReject,
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Reject")
                }
            }
        }
    }
}

@Composable
private fun FingerprintCard(
    fingerprint: String,
    dimmed: Boolean = false
) {
    // Parse fingerprint: "xxyy:xxyy:xxyy  emoji1 emoji2 emoji3 emoji4 emoji5 emoji6"
    val parts = fingerprint.split("  ", limit = 2)
    val hexPart = parts.getOrElse(0) { fingerprint }
    val emojiPart = parts.getOrElse(1) { "" }
    val emojis = emojiPart.split(" ").filter { it.isNotBlank() }

    val alpha = if (dimmed) 0.5f else 1f

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = alpha)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Hex fingerprint
            Text(
                text = hexPart,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = alpha)
            )

            if (emojis.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))

                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f * alpha)
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Emoji row 1 (first 3)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    emojis.take(3).forEach { emoji ->
                        Text(
                            text = emoji,
                            fontSize = 32.sp
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Emoji row 2 (last 3)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    emojis.drop(3).take(3).forEach { emoji ->
                        Text(
                            text = emoji,
                            fontSize = 32.sp
                        )
                    }
                }
            }
        }
    }
}
