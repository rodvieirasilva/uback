package uback.rodvieirasilva.github.io

import android.os.Environment
import java.io.File

data class ClassifiedSource(
    val sourceId: String,
    val remoteSubpath: String,
)

/**
 * Classifies MediaStore paths and scans direct filesystem directories (e.g., WhatsApp Sent /
 * Voice Notes containing `.nomedia` and Samsung Voice Recorder folders) cleanly.
 */
object MediaSourceClassifier {

    val ALL_SOURCE_IDS: Set<String> = setOf(
        "camera.images",
        "camera.videos",
        "screenshots",
        "whatsapp.received.images",
        "whatsapp.received.videos",
        "whatsapp.received.audios",
        "whatsapp.sent.images",
        "whatsapp.sent.videos",
        "whatsapp.sent.audios",
        "recordings",
    )

    private val IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "dng", "bmp")
    private val VIDEO_EXTS = setOf("mp4", "mkv", "mov", "3gp", "webm", "avi", "m4v")
    private val AUDIO_EXTS = setOf("opus", "m4a", "mp3", "aac", "ogg", "wav", "amr", "3ga", "flac", "awb")

    fun mediaKindFromPath(fileName: String, mimeType: String?): String? {
        val m = (mimeType ?: "").lowercase()
        if (m.startsWith("image/")) return "image"
        if (m.startsWith("video/")) return "video"
        if (m.startsWith("audio/")) return "audio"

        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when {
            ext in IMAGE_EXTS -> "image"
            ext in VIDEO_EXTS -> "video"
            ext in AUDIO_EXTS -> "audio"
            else -> null
        }
    }

    fun classify(relativePath: String?, absolutePath: String?, mediaKind: String): ClassifiedSource? {
        val norm = normalizePath(relativePath, absolutePath)
        if (norm.isEmpty()) return null

        // 1. Camera (split by Images / Videos)
        if (matchesPrefix(norm, "dcim/camera")) {
            return when (mediaKind) {
                "image" -> ClassifiedSource("camera.images", "camera")
                "video" -> ClassifiedSource("camera.videos", "camera")
                else -> null
            }
        }

        // 2. Screenshots (Samsung DCIM/Screenshots + stock Android Pictures/Screenshots)
        if (matchesPrefix(norm, "dcim/screenshots") || matchesPrefix(norm, "pictures/screenshots")) {
            if (mediaKind == "image" || mediaKind == "video") {
                return ClassifiedSource("screenshots", "screenshots")
            }
            return null
        }

        // 3. WhatsApp (Android 11+ Android/media/com.whatsapp/..., legacy WhatsApp/Media/..., or Pictures/WhatsApp ...)
        val wa = classifyWhatsApp(norm, mediaKind)
        if (wa != null) return wa

        // 4. Recorded Audios (Samsung Voice Recorder, Recordings, SoundRecorder, CallRecordings)
        if (mediaKind == "audio" && isRecordingPath(norm)) {
            return ClassifiedSource("recordings", "recordings")
        }

        return null
    }

    private fun classifyWhatsApp(norm: String, mediaKind: String): ClassifiedSource? {
        if (!norm.contains("whatsapp")) return null
        val isSent = norm.contains("/sent/") || norm.endsWith("/sent")

        // WhatsApp Voice Notes (nested date folders, always audio)
        if (norm.contains("whatsapp voice notes")) {
            if (mediaKind != "audio") return null
            return if (isSent) {
                ClassifiedSource("whatsapp.sent.audios", "whatsapp/sent/audios")
            } else {
                ClassifiedSource("whatsapp.received.audios", "whatsapp/received/audios")
            }
        }

        if (norm.contains("whatsapp images")) {
            if (mediaKind != "image") return null
            return if (isSent) {
                ClassifiedSource("whatsapp.sent.images", "whatsapp/sent/images")
            } else {
                ClassifiedSource("whatsapp.received.images", "whatsapp/received/images")
            }
        }

        if (norm.contains("whatsapp video")) {
            if (mediaKind != "video") return null
            return if (isSent) {
                ClassifiedSource("whatsapp.sent.videos", "whatsapp/sent/videos")
            } else {
                ClassifiedSource("whatsapp.received.videos", "whatsapp/received/videos")
            }
        }

        if (norm.contains("whatsapp audio")) {
            if (mediaKind != "audio") return null
            return if (isSent) {
                ClassifiedSource("whatsapp.sent.audios", "whatsapp/sent/audios")
            } else {
                ClassifiedSource("whatsapp.received.audios", "whatsapp/received/audios")
            }
        }

        return null
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

    private fun normalizePath(relativePath: String?, absolutePath: String?): String {
        val raw = (absolutePath?.takeIf { it.isNotBlank() } ?: relativePath ?: "")
            .replace('\\', '/')
            .lowercase()

        // Strip `/storage/emulated/<user>/` or `/sdcard/` prefix so path matching is uniform.
        val stripped = raw
            .replace(Regex("^/storage/emulated/\\d+/"), "")
            .replace(Regex("^/sdcard/"), "")
            .trim('/')

        // If absolutePath pointed to a file, keep only its parent directory path.
        val lastSlash = stripped.lastIndexOf('/')
        return if (!absolutePath.isNullOrBlank() && lastSlash > 0) {
            stripped.substring(0, lastSlash)
        } else {
            stripped
        }
    }

    private fun matchesPrefix(dir: String, prefix: String): Boolean {
        return dir == prefix || dir.startsWith("$prefix/")
    }

    /**
     * Direct filesystem roots that may contain `.nomedia` (like WhatsApp Sent & Voice Notes)
     * or audio recordings not yet indexed by MediaStore.
     */
    fun directScanRoots(): List<File> {
        val root = Environment.getExternalStorageDirectory()
        val candidates = listOf(
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio",
            "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes",
            "WhatsApp/Media/WhatsApp Images",
            "WhatsApp/Media/WhatsApp Video",
            "WhatsApp/Media/WhatsApp Audio",
            "WhatsApp/Media/WhatsApp Voice Notes",
            "Pictures/WhatsApp Images",
            "Movies/WhatsApp Video",
            "Music/WhatsApp Audio",
            "Recordings",
            "Voice Recorder",
            "SoundRecorder",
            "CallRecordings",
            "Music/Recordings",
        )
        return candidates.map { File(root, it) }.filter { it.exists() && it.isDirectory }
    }

    fun mimeTypeFor(fileName: String, mediaKind: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "heic", "heif" -> "image/heic"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "opus" -> "audio/opus"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "ogg" -> "audio/ogg"
            "wav" -> "audio/wav"
            "amr" -> "audio/amr"
            else -> "$mediaKind/*"
        }
    }
}
