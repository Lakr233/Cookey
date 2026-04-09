package wiki.qaq.cookey.ui.settings

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import wiki.qaq.cookey.service.TrustedKey
import wiki.qaq.cookey.service.TrustedKeyStore
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrustedKeysScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var keys by remember { mutableStateOf(TrustedKeyStore.allKeys(context)) }
    var searchQuery by remember { mutableStateOf("") }
    var isSelecting by remember { mutableStateOf(false) }
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }

    val filteredKeys = remember(keys, searchQuery) {
        if (searchQuery.isBlank()) keys
        else keys.filter { key ->
            key.deviceID.contains(searchQuery, ignoreCase = true) ||
                key.publicKeyBase64.contains(searchQuery, ignoreCase = true) ||
                key.fingerprint.contains(searchQuery, ignoreCase = true) ||
                key.label?.contains(searchQuery, ignoreCase = true) == true
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Trusted Keys") },
                navigationIcon = {
                    IconButton(onClick = {
                        if (isSelecting) {
                            isSelecting = false
                            selectedIds = emptySet()
                        } else {
                            onBack()
                        }
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    if (isSelecting) {
                        if (selectedIds.isNotEmpty()) {
                            TextButton(onClick = { showDeleteConfirmation = true }) {
                                Text(
                                    "Delete (${selectedIds.size})",
                                    color = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                        TextButton(onClick = {
                            isSelecting = false
                            selectedIds = emptySet()
                        }) {
                            Text("Done")
                        }
                    } else if (keys.isNotEmpty()) {
                        IconButton(onClick = { isSelecting = true }) {
                            Icon(Icons.Default.Checklist, "Select")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Search bar
            if (keys.isNotEmpty()) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    placeholder = { Text("Search keys...") },
                    leadingIcon = { Icon(Icons.Default.Search, null) },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Clear, "Clear")
                            }
                        }
                    },
                    singleLine = true
                )
            }

            if (filteredKeys.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.VpnKey,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.outlineVariant
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            if (keys.isEmpty()) "No trusted keys yet"
                            else "No matching keys",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize()
                ) {
                    items(
                        items = filteredKeys,
                        key = { it.deviceID }
                    ) { key ->
                        val isSelected = selectedIds.contains(key.deviceID)
                        val dismissState = rememberSwipeToDismissBoxState(
                            confirmValueChange = { value ->
                                if (value == SwipeToDismissBoxValue.EndToStart) {
                                    TrustedKeyStore.removeKey(context, key.deviceID)
                                    keys = TrustedKeyStore.allKeys(context)
                                    true
                                } else false
                            }
                        )

                        if (!isSelecting) {
                            SwipeToDismissBox(
                                state = dismissState,
                                backgroundContent = {
                                    val color by animateColorAsState(
                                        if (dismissState.targetValue == SwipeToDismissBoxValue.EndToStart)
                                            MaterialTheme.colorScheme.errorContainer
                                        else MaterialTheme.colorScheme.surface,
                                        label = "bg"
                                    )
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .background(color)
                                            .padding(horizontal = 20.dp),
                                        contentAlignment = Alignment.CenterEnd
                                    ) {
                                        Icon(
                                            Icons.Default.Delete,
                                            contentDescription = "Delete",
                                            tint = MaterialTheme.colorScheme.onErrorContainer
                                        )
                                    }
                                },
                                enableDismissFromStartToEnd = false
                            ) {
                                TrustedKeyItem(key = key)
                            }
                        } else {
                            Surface(
                                onClick = {
                                    selectedIds = if (isSelected)
                                        selectedIds - key.deviceID
                                    else
                                        selectedIds + key.deviceID
                                },
                                color = if (isSelected)
                                    MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                                else
                                    MaterialTheme.colorScheme.surface
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Checkbox(
                                        checked = isSelected,
                                        onCheckedChange = {
                                            selectedIds = if (isSelected)
                                                selectedIds - key.deviceID
                                            else
                                                selectedIds + key.deviceID
                                        },
                                        modifier = Modifier.padding(start = 8.dp)
                                    )
                                    TrustedKeyItem(key = key, modifier = Modifier.weight(1f))
                                }
                            }
                        }
                        HorizontalDivider()
                    }
                }
            }
        }
    }

    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text("Delete ${selectedIds.size} Key${if (selectedIds.size > 1) "s" else ""}?") },
            text = { Text("This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        selectedIds.forEach { id ->
                            TrustedKeyStore.removeKey(context, id)
                        }
                        keys = TrustedKeyStore.allKeys(context)
                        selectedIds = emptySet()
                        isSelecting = false
                        showDeleteConfirmation = false
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun TrustedKeyItem(
    key: TrustedKey,
    modifier: Modifier = Modifier
) {
    val dateFormatter = remember {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)
            .withZone(ZoneId.systemDefault())
    }

    val lastSeen = try {
        dateFormatter.format(Instant.parse(key.lastSeenAt))
    } catch (_: Exception) {
        key.lastSeenAt
    }

    ListItem(
        modifier = modifier,
        headlineContent = {
            Text(
                text = key.fingerprint,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium
            )
        },
        supportingContent = {
            Text("Last seen: $lastSeen")
        },
        leadingContent = {
            Icon(
                Icons.Default.VpnKey,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        }
    )
}
