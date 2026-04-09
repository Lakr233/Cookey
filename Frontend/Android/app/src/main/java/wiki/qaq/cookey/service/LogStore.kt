package wiki.qaq.cookey.service

import android.content.Context
import java.io.File
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

enum class LogLevel(val label: String) {
    DEBUG("DEBUG"),
    INFO("INFO"),
    ERROR("ERROR")
}

enum class LogCategory(val label: String) {
    UI("ui"),
    NETWORK("network"),
    PUSH("push"),
    BROWSER("browser"),
    MODEL("model"),
    APP("app"),
    CRYPTO("crypto")
}

data class LogEntry(
    val timestamp: String,
    val level: LogLevel,
    val category: LogCategory,
    val message: String
) {
    val displayText: String get() = "$timestamp [$level] [$category] $message"
}

object LogStore {

    private const val MAX_FILE_SIZE = 5L * 1024 * 1024 // 5 MB
    private const val MAX_ROTATED_FILES = 5
    private const val LOG_FILENAME = "Cookey.log"
    private const val TAIL_MAX_BYTES = 512 * 1024L // 512 KB

    private val executor = Executors.newSingleThreadExecutor()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private var logFile: File? = null

    private fun ensureLogFile(context: Context): File {
        logFile?.let { return it }
        val dir = File(context.cacheDir, "Logs")
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, LOG_FILENAME)
        logFile = file
        return file
    }

    fun append(context: Context, level: LogLevel, category: LogCategory, message: String) {
        executor.execute {
            try {
                val file = ensureLogFile(context)
                rotateIfNeeded(file)
                val timestamp = dateFormat.format(Date())
                val line = "$timestamp [${level.label}] [${category.label}] $message\n"
                file.appendText(line)
            } catch (_: Exception) {
                // Logging should never crash the app
            }
        }
    }

    private fun rotateIfNeeded(file: File) {
        if (!file.exists() || file.length() < MAX_FILE_SIZE) return
        val dir = file.parentFile ?: return

        // Delete oldest rotated file
        val oldest = File(dir, "$LOG_FILENAME.$MAX_ROTATED_FILES")
        if (oldest.exists()) oldest.delete()

        // Shift existing rotated files
        for (i in (MAX_ROTATED_FILES - 1) downTo 1) {
            val src = File(dir, "$LOG_FILENAME.$i")
            val dst = File(dir, "$LOG_FILENAME.${i + 1}")
            if (src.exists()) src.renameTo(dst)
        }

        // Rotate current file
        val first = File(dir, "$LOG_FILENAME.1")
        file.renameTo(first)
    }

    fun readTail(context: Context, maxBytes: Long = TAIL_MAX_BYTES): String {
        val file = ensureLogFile(context)
        if (!file.exists() || file.length() == 0L) return ""

        return try {
            if (file.length() <= maxBytes) {
                file.readText()
            } else {
                RandomAccessFile(file, "r").use { raf ->
                    raf.seek(file.length() - maxBytes)
                    // Skip partial first line
                    raf.readLine()
                    val remaining = ByteArray((file.length() - raf.filePointer).toInt())
                    raf.readFully(remaining)
                    String(remaining, Charsets.UTF_8)
                }
            }
        } catch (_: Exception) {
            ""
        }
    }

    fun parseEntries(context: Context): List<LogEntry> {
        val text = readTail(context)
        if (text.isBlank()) return emptyList()

        val pattern = Regex("""^(\S+)\s+\[(\w+)]\s+\[(\w+)]\s+(.*)$""")
        return text.lines().mapNotNull { line ->
            val match = pattern.matchEntire(line) ?: return@mapNotNull null
            val (timestamp, levelStr, categoryStr, message) = match.destructured
            val level = LogLevel.entries.find { it.label.equals(levelStr, ignoreCase = true) } ?: LogLevel.INFO
            val category = LogCategory.entries.find { it.label.equals(categoryStr, ignoreCase = true) } ?: LogCategory.APP
            LogEntry(timestamp, level, category, message)
        }
    }

    fun clear(context: Context) {
        executor.execute {
            try {
                val file = ensureLogFile(context)
                val dir = file.parentFile ?: return@execute
                file.delete()
                for (i in 1..MAX_ROTATED_FILES) {
                    File(dir, "$LOG_FILENAME.$i").delete()
                }
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    // Convenience methods
    fun debug(context: Context, category: LogCategory, message: String) =
        append(context, LogLevel.DEBUG, category, message)

    fun info(context: Context, category: LogCategory, message: String) =
        append(context, LogLevel.INFO, category, message)

    fun error(context: Context, category: LogCategory, message: String) =
        append(context, LogLevel.ERROR, category, message)
}
