package uback.rodvieirasilva.github.io

import android.os.Environment
import java.io.File

data class ClassifiedSource(
    val sourceId: String,
    val remoteSubpath: String,
)

data class CustomFolderSpec(
    val id: String,
    val relativePath: String,
    val remoteSubpath: String,
) {
    val normalizedRelativePath: String = relativePath
        .replace('\\', '/')
        .replace(Regex("^/storage/emulated/\\d+/"), "")
        .replace(Regex("^/sdcard/"), "")
        .trim('/')
        .lowercase()

    companion object {
        fun fromMap(map: Map<*, *>): CustomFolderSpec? {
            val id = (map["id"] as? String)?.trim().orEmpty()
            val rel = (map["relativePath"] as? String)?.trim().orEmpty()
            if (id.isEmpty() || rel.isEmpty()) return null
            val slug = (map["slug"] as? String)?.trim().takeIf { !it.isNullOrEmpty() }
                ?: id.removePrefix("custom.").ifBlank { "folder" }
            return CustomFolderSpec(
                id = id,
                relativePath = rel,
                remoteSubpath = "custom/$slug",
            )
        }
    }
}

/**
 * Classifies MediaStore and filesystem paths into leaf MediaSource IDs and remote subpaths.
 */
object MediaSourceClassifier {

    val BUILTIN_FILE_SOURCE_IDS: Set<String> = setOf(
        "camera.images",
        "camera.videos",
        "camera.raw",
        "screenshots",
        "screen_recordings",
        "whatsapp.received.images",
        "whatsapp.received.videos",
        "whatsapp.received.audios",
        "whatsapp.received.documents",
        "whatsapp.sent.images",
        "whatsapp.sent.videos",
        "whatsapp.sent.audios",
        "whatsapp.sent.documents",
        "whatsapp_business.received.images",
        "whatsapp_business.received.videos",
        "whatsapp_business.received.audios",
        "whatsapp_business.received.documents",
        "whatsapp_business.sent.images",
        "whatsapp_business.sent.videos",
        "whatsapp_business.sent.audios",
        "whatsapp_business.sent.documents",
        "telegram.images",
        "telegram.videos",
        "telegram.audios",
        "telegram.documents",
        "editors.lightroom",
        "editors.snapseed",
        "editors.instagram",
        "editors.other",
        "recordings",
        "documents",
        "downloads.media",
        "downloads.documents",
        "downloads.other",
    )

    val SNAPSHOT_SOURCE_IDS: Set<String> = setOf(
        "snapshots.contacts",
        "snapshots.sms",
        "snapshots.call_logs",
    )

    val ALL_BUILTIN_SOURCE_IDS: Set<String> = BUILTIN_FILE_SOURCE_IDS + SNAPSHOT_SOURCE_IDS

    private val IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "dng", "bmp", "tif", "tiff")
    private val VIDEO_EXTS = setOf("mp4", "mkv", "mov", "3gp", "webm", "avi", "m4v")
    private val AUDIO_EXTS = setOf("opus", "m4a", "mp3", "aac", "ogg", "wav", "amr", "3ga", "flac", "awb")
    private val DOC_EXTS = setOf(
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "csv",
        "rtf", "odt", "ods", "odp", "epub", "json", "xml", "vcf",
    )

    fun fileKindFromPath(fileName: String, mimeType: String?): String {
        val m = (mimeType ?: "").lowercase()
        if (m.startsWith("image/")) return "image"
        if (m.startsWith("video/")) return "video"
        if (m.startsWith("audio/")) return "audio"

        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when {
            ext in IMAGE_EXTS -> "image"
            ext in VIDEO_EXTS -> "video"
            ext in AUDIO_EXTS -> "audio"
            ext in DOC_EXTS -> "document"
            else -> "other"
        }
    }

    fun classify(
        relativePath: String?,
        absolutePath: String?,
        fileKind: String,
        customFolders: List<CustomFolderSpec> = emptyList(),
    ): ClassifiedSource? {
        val norm = normalizeDir(relativePath, absolutePath)
        if (norm.isEmpty()) return null

        // 0. Custom folders (matched first so user-defined folders always take precedence)
        for (custom in customFolders) {
            val prefix = custom.normalizedRelativePath
            if (prefix.isNotEmpty() && matchesPrefix(norm, prefix)) {
                return ClassifiedSource(custom.id, custom.remoteSubpath)
            }
        }

        // 1. Camera (Images, Videos, Samsung Expert RAW)
        if (matchesPrefix(norm, "dcim/expert raw")) {
            return ClassifiedSource("camera.raw", "camera/raw")
        }
        if (matchesPrefix(norm, "dcim/camera")) {
            return when (fileKind) {
                "image" -> ClassifiedSource("camera.images", "camera")
                "video" -> ClassifiedSource("camera.videos", "camera")
                else -> null
            }
        }

        // 2. Screenshots & Screen Recordings
        if (matchesPrefix(norm, "dcim/screenshots") || matchesPrefix(norm, "pictures/screenshots")) {
            if (fileKind == "image" || fileKind == "video") {
                return ClassifiedSource("screenshots", "screenshots")
            }
            return null
        }
        if (matchesPrefix(norm, "dcim/screen recordings") || matchesPrefix(norm, "movies/screenrecords")) {
            if (fileKind == "video" || fileKind == "image") {
                return ClassifiedSource("screen_recordings", "screen-recordings")
            }
            return null
        }

        // 3. WhatsApp Business (must be checked BEFORE regular WhatsApp!)
        if (norm.contains("whatsapp business") || norm.contains("com.whatsapp.w4b")) {
            return classifyWhatsAppFamily(norm, fileKind, "whatsapp_business", "whatsapp-business")
        }

        // 4. WhatsApp
        if (norm.contains("whatsapp")) {
            return classifyWhatsAppFamily(norm, fileKind, "whatsapp", "whatsapp")
        }

        // 5. Telegram
        if (norm.contains("telegram")) {
            return classifyTelegram(norm, fileKind)
        }

        // 6. Photo Editors & Social
        if (matchesPrefix(norm, "pictures/lightroom")) {
            return ClassifiedSource("editors.lightroom", "editors/lightroom")
        }
        if (matchesPrefix(norm, "pictures/snapseed")) {
            return ClassifiedSource("editors.snapseed", "editors/snapseed")
        }
        if (matchesPrefix(norm, "pictures/instagram") || matchesPrefix(norm, "movies/instagram")) {
            return ClassifiedSource("editors.instagram", "editors/instagram")
        }
        if (
            matchesPrefix(norm, "dcim/restored") ||
            matchesPrefix(norm, "pictures/canva") ||
            matchesPrefix(norm, "dcim/100pint")
        ) {
            return ClassifiedSource("editors.other", "editors/other")
        }

        // 7. Recorded Audios
        if (fileKind == "audio" && isRecordingPath(norm)) {
            return ClassifiedSource("recordings", "recordings")
        }

        // 8. Documents
        if (matchesPrefix(norm, "documents")) {
            return ClassifiedSource("documents", "documents")
        }

        // 9. Downloads (split into Media / Documents / Other)
        if (matchesPrefix(norm, "download") || matchesPrefix(norm, "downloads")) {
            return when (fileKind) {
                "image", "video" -> ClassifiedSource("downloads.media", "downloads/media")
                "document" -> ClassifiedSource("downloads.documents", "downloads/documents")
                else -> ClassifiedSource("downloads.other", "downloads/other")
            }
        }

        return null
    }

    private fun classifyWhatsAppFamily(
        norm: String,
        fileKind: String,
        idPrefix: String,
        remotePrefix: String,
    ): ClassifiedSource? {
        val isSent = norm.contains("/sent/") || norm.endsWith("/sent")
        val dir = if (isSent) "sent" else "received"

        if (norm.contains("voice notes")) {
            if (fileKind != "audio") return null
            return ClassifiedSource("$idPrefix.$dir.audios", "$remotePrefix/$dir/audios")
        }
        if (norm.contains("images")) {
            if (fileKind != "image") return null
            return ClassifiedSource("$idPrefix.$dir.images", "$remotePrefix/$dir/images")
        }
        if (norm.contains("video")) {
            if (fileKind != "video") return null
            return ClassifiedSource("$idPrefix.$dir.videos", "$remotePrefix/$dir/videos")
        }
        if (norm.contains("audio")) {
            if (fileKind != "audio") return null
            return ClassifiedSource("$idPrefix.$dir.audios", "$remotePrefix/$dir/audios")
        }
        if (norm.contains("documents")) {
            return ClassifiedSource("$idPrefix.$dir.documents", "$remotePrefix/$dir/documents")
        }
        return null
    }

    private fun classifyTelegram(norm: String, fileKind: String): ClassifiedSource? {
        return when {
            norm.contains("telegram documents") || fileKind == "document" ->
                ClassifiedSource("telegram.documents", "telegram/documents")
            norm.contains("telegram audio") || fileKind == "audio" ->
                ClassifiedSource("telegram.audios", "telegram/audios")
            norm.contains("telegram video") || fileKind == "video" ->
                ClassifiedSource("telegram.videos", "telegram/videos")
            norm.contains("telegram images") || fileKind == "image" ->
                ClassifiedSource("telegram.images", "telegram/images")
            else -> ClassifiedSource("telegram.documents", "telegram/documents")
        }
    }

    private fun isRecordingPath(norm: String): Boolean {
        return matchesPrefix(norm, "recordings") ||
            matchesPrefix(norm, "voice recorder") ||
            matchesPrefix(norm, "soundrecorder") ||
            matchesPrefix(norm, "callrecordings") ||
            matchesPrefix(norm, "music/recordings") ||
            matchesPrefix(norm, "miui/sound_recorder") ||
            matchesPrefix(norm, "audiorecorder") ||
            matchesPrefix(norm, "call")
    }

    private fun normalizeDir(relativePath: String?, absolutePath: String?): String {
        val raw = (absolutePath?.takeIf { it.isNotBlank() } ?: relativePath ?: "")
            .replace('\\', '/')
            .lowercase()

        val stripped = raw
            .replace(Regex("^/storage/emulated/\\d+/"), "")
            .replace(Regex("^/sdcard/"), "")
            .trim('/')

        val lastSlash = stripped.lastIndexOf('/')
        return if (!absolutePath.isNullOrBlank() && lastSlash > 0) {
            stripped.substring(0, lastSlash)
        } else {
            stripped
        }
    }

    private fun matchesPrefix(dir: String, prefix: String): Boolean =
        dir == prefix || dir.startsWith("$prefix/")

    /**
     * Direct filesystem roots covering `.nomedia` folders (WhatsApp Sent/Voice Notes/Documents,
     * Telegram, etc.), Documents, Downloads, Screen Recordings, RAW, Editors, and Custom Folders.
     */
    fun directScanRoots(customFolders: List<CustomFolderSpec> = emptyList()): List<File> {
        val root = Environment.getExternalStorageDirectory()
        val builtInPaths = listOf(
            "DCIM/Expert RAW",
            "DCIM/Screen recordings",
            "Movies/Screenrecords",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents",
            "WhatsApp/Media/WhatsApp Images",
            "WhatsApp/Media/WhatsApp Video",
            "WhatsApp/Media/WhatsApp Audio",
            "WhatsApp/Media/WhatsApp Voice Notes",
            "WhatsApp/Media/WhatsApp Documents",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Images",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Video",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Audio",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Voice Notes",
            "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Business Documents",
            "Android/media/org.telegram.messenger/Telegram",
            "Pictures/Telegram",
            "Movies/Telegram",
            "Download/Telegram",
            "Pictures/WhatsApp Images",
            "Movies/WhatsApp Video",
            "Music/WhatsApp Audio",
            "Pictures/Lightroom",
            "Pictures/Snapseed",
            "Pictures/Instagram",
            "Movies/Instagram",
            "DCIM/Restored",
            "Pictures/Canva",
            "DCIM/100PINT",
            "Recordings",
            "Voice Recorder",
            "SoundRecorder",
            "CallRecordings",
            "Music/Recordings",
            "Documents",
            "Download",
        )
        val allPaths = builtInPaths + customFolders.map { it.relativePath.trim('/') }
        return allPaths
            .map { File(root, it) }
            .filter { it.exists() && it.isDirectory }
            .distinctBy { runCatching { it.canonicalPath }.getOrDefault(it.absolutePath) }
    }

    fun mimeTypeFor(fileName: String, fileKind: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "heic", "heif" -> "image/heic"
            "dng" -> "image/x-adobe-dng"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "opus" -> "audio/opus"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "ogg" -> "audio/ogg"
            "wav" -> "audio/wav"
            "amr" -> "audio/amr"
            "pdf" -> "application/pdf"
            "txt", "md", "csv" -> "text/plain"
            "json" -> "application/json"
            "vcf" -> "text/vcard"
            else -> if (fileKind in setOf("image", "video", "audio")) "$fileKind/*" else "application/octet-stream"
        }
    }
}
