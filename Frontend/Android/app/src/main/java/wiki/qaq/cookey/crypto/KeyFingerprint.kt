package wiki.qaq.cookey.crypto

import android.util.Base64
import java.security.MessageDigest

object KeyFingerprint {

    val emojiTable: List<String> = listOf(
        // 0x00–0x0F
        "🍎", "🍊", "🍋", "🍇", "🍉", "🍓", "🫐", "🍒",
        "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍆", "🥑",
        // 0x10–0x1F
        "🥦", "🥬", "🥒", "🌶", "🫑", "🌽", "🥕", "🫒",
        "🧄", "🧅", "🥔", "🍠", "🥐", "🥯", "🍞", "🧀",
        // 0x20–0x2F
        "🥚", "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖",
        "🌭", "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆",
        // 0x30–0x3F
        "🌮", "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🍝",
        "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤",
        // 0x40–0x4F
        "🍙", "🍚", "🍘", "🍥", "🥠", "🥮", "🍢", "🍡",
        "🍧", "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮",
        // 0x50–0x5F
        "🍭", "🍬", "🍫", "🍩", "🍪", "🌰", "🥜", "🫘",
        "🍯", "🥛", "🍼", "🫖", "🍵", "🧃", "🥤", "🧋",
        // 0x60–0x6F
        "🍺", "🍻", "🥂", "🍷", "🫗", "🍸", "🍹", "🧉",
        "🍾", "🧊", "🥄", "🍴", "🥣", "🥡", "🥢", "🧂",
        // 0x70–0x7F
        "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉",
        "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🥍", "🏏",
        // 0x80–0x8F
        "🪃", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿", "🥊",
        "🥋", "🎽", "🛹", "🛼", "🛷", "⛸", "🥌", "🎿",
        // 0x90–0x9F
        "🎯", "🪀", "🎲", "🧩", "🎰", "🎳", "🎮", "🕹",
        "🎻", "🎸", "🎺", "🎷", "🪗", "🥁", "🪘", "🎹",
        // 0xA0–0xAF
        "🔔", "🎵", "🎶", "🎤", "🎧", "📻", "🎙", "📯",
        "🔕", "🔊", "🔉", "🔈", "📢", "📣", "🔇", "🪈",
        // 0xB0–0xBF
        "🌍", "🌎", "🌏", "🌐", "🧭", "🏔", "⛰", "🌋",
        "🗻", "🏕", "🏖", "🏜", "🏝", "🏞", "🏟", "🏛",
        // 0xC0–0xCF
        "🏗", "🧱", "🪨", "🪵", "🛖", "🏘", "🏚", "🏠",
        "🏡", "🏢", "🏣", "🏤", "🏥", "🏦", "🏨", "🏩",
        // 0xD0–0xDF
        "🏪", "🏫", "🏬", "🏭", "🏯", "🏰", "💒", "🗼",
        "🗽", "⛪", "🕌", "🛕", "🕍", "⛩", "🕋", "⛲",
        // 0xE0–0xEF
        "🌁", "🌃", "🏙", "🌄", "🌅", "🌆", "🌇", "🌉",
        "🎠", "🛝", "🎡", "🎢", "💈", "🎪", "🚂", "🚃",
        // 0xF0–0xFF
        "🚄", "🚅", "🚆", "🚇", "🚈", "🚉", "🚊", "🚝",
        "🚞", "🚋", "🚌", "🚍", "🚎", "🚐", "🚑", "🚒"
    )

    fun compute(fromX25519PublicKeyBase64: String): String {
        val keyData = Base64.decode(fromX25519PublicKeyBase64, Base64.DEFAULT)
        require(keyData.size == 32) { "Invalid X25519 public key size: ${keyData.size}" }

        val hash = MessageDigest.getInstance("SHA-256").digest(keyData)

        // Bytes 0–5 → hex formatted as "xxyy:xxyy:xxyy"
        val hex = String.format(
            "%02x%02x:%02x%02x:%02x%02x",
            hash[0].toInt() and 0xFF, hash[1].toInt() and 0xFF,
            hash[2].toInt() and 0xFF, hash[3].toInt() and 0xFF,
            hash[4].toInt() and 0xFF, hash[5].toInt() and 0xFF
        )

        // Bytes 6–11 → 6 emoji from lookup table
        val emojis = (6..11).joinToString(" ") { emojiTable[hash[it].toInt() and 0xFF] }

        return "$hex  $emojis"
    }
}
