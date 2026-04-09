package wiki.qaq.cookey.ui.settings

import android.content.Intent
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import wiki.qaq.cookey.service.LogCategory
import wiki.qaq.cookey.service.LogEntry
import wiki.qaq.cookey.service.LogLevel
import wiki.qaq.cookey.service.LogStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogViewerScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var entries by remember { mutableStateOf(LogStore.parseEntries(context)) }
    var searchQuery by remember { mutableStateOf("") }
    var selectedLevels by remember { mutableStateOf(LogLevel.entries.toSet()) }
    var selectedCategories by remember { mutableStateOf(LogCategory.entries.toSet()) }
    var showFilterMenu by remember { mutableStateOf(false) }
    var showSensitiveWarning by remember { mutableStateOf(true) }

    val filteredEntries = remember(entries, searchQuery, selectedLevels, selectedCategories) {
        entries.filter { entry ->
            entry.level in selectedLevels &&
                entry.category in selectedCategories &&
                (searchQuery.isBlank() || entry.message.contains(searchQuery, ignoreCase = true))
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Logs") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        entries = LogStore.parseEntries(context)
                    }) {
                        Icon(Icons.Default.Refresh, "Refresh")
                    }

                    Box {
                        IconButton(onClick = { showFilterMenu = true }) {
                            Icon(Icons.Default.FilterList, "Filter")
                        }
                        DropdownMenu(
                            expanded = showFilterMenu,
                            onDismissRequest = { showFilterMenu = false }
                        ) {
                            Text(
                                "Log Level",
                                style = MaterialTheme.typography.labelMedium,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                                color = MaterialTheme.colorScheme.primary
                            )
                            LogLevel.entries.forEach { level ->
                                DropdownMenuItem(
                                    text = { Text(level.label) },
                                    onClick = {
                                        selectedLevels = if (level in selectedLevels)
                                            selectedLevels - level
                                        else
                                            selectedLevels + level
                                    },
                                    leadingIcon = {
                                        Checkbox(
                                            checked = level in selectedLevels,
                                            onCheckedChange = null
                                        )
                                    }
                                )
                            }
                            HorizontalDivider()
                            Text(
                                "Category",
                                style = MaterialTheme.typography.labelMedium,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                                color = MaterialTheme.colorScheme.primary
                            )
                            LogCategory.entries.forEach { category ->
                                DropdownMenuItem(
                                    text = { Text(category.label) },
                                    onClick = {
                                        selectedCategories = if (category in selectedCategories)
                                            selectedCategories - category
                                        else
                                            selectedCategories + category
                                    },
                                    leadingIcon = {
                                        Checkbox(
                                            checked = category in selectedCategories,
                                            onCheckedChange = null
                                        )
                                    }
                                )
                            }
                        }
                    }

                    IconButton(onClick = {
                        val text = LogStore.readTail(context)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, text)
                            putExtra(Intent.EXTRA_SUBJECT, "Cookey Logs")
                        }
                        context.startActivity(Intent.createChooser(intent, "Share Logs"))
                    }) {
                        Icon(Icons.Default.Share, "Share")
                    }

                    IconButton(onClick = {
                        LogStore.clear(context)
                        entries = emptyList()
                    }) {
                        Icon(Icons.Default.DeleteSweep, "Clear")
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
            // Sensitive data warning
            if (showSensitiveWarning && entries.isNotEmpty()) {
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.5f)
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.error
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "Logs may contain sensitive data such as URLs and session details.",
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(
                            onClick = { showSensitiveWarning = false },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(Icons.Default.Close, "Dismiss", modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }

            // Search bar
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search logs...") },
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

            if (filteredEntries.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        if (entries.isEmpty()) "No logs yet" else "No matching entries",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = rememberLazyListState()
                ) {
                    items(filteredEntries) { entry ->
                        LogEntryItem(entry)
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

@Composable
private fun LogEntryItem(entry: LogEntry) {
    val levelColor = when (entry.level) {
        LogLevel.DEBUG -> MaterialTheme.colorScheme.onSurfaceVariant
        LogLevel.INFO -> MaterialTheme.colorScheme.onSurface
        LogLevel.ERROR -> MaterialTheme.colorScheme.error
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(
            text = entry.message,
            fontFamily = FontFamily.Monospace,
            fontSize = 13.sp,
            color = levelColor,
            modifier = Modifier.horizontalScroll(rememberScrollState())
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = "${entry.timestamp}  [${entry.category.label}]",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 11.sp
        )
    }
}
