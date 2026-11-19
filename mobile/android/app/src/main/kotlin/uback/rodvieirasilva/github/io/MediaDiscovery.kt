package uback.rodvieirasilva.github.io

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import java.io.File

data class DiscoveredMediaItem(
    val id: String,
    val contentUri: String,
    val fileName: String,
    val localPath: String,
    val sourceFolder: String,
    val sizeBytes: Long,
    val createdAtMs: Long,
    val mimeType: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "id" to id,
        "contentUri" to contentUri,
        "fileName" to fileName,
        "localPath" to localPath,
        "sourceFolder" to sourceFolder,
        "sizeBytes" to sizeBytes,
        "createdAtMs" to createdAtMs,
        "mimeType" to mimeType,
    )
}

object MediaDiscovery {

    fun getDeviceName(context: Context): String {
        val globalName = runCatching {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        }.getOrNull()
        if (!globalName.isNullOrBlank()) {
            return globalName.trim()
        }
        val secureName = runCatching {
            Settings.Secure.getString(context.contentResolver, "bluetooth_name")
        }.getOrNull()
        if (!secureName.isNullOrBlank()) {
            return secureName.trim()
        }
        return Build.MODEL ?: "android"
    }

    /**
     * Classifies a MediaStore item into Phase 1 sources strictly:
     * - "camera": DCIM/Camera
     * - "screenshots": DCIM/Screenshots (Samsung One UI) or Pictures/Screenshots (stock Android/Emulator)
     * Returns null for all other folders (e.g. WhatsApp, Download, etc.) so they are excluded in Phase 1.
     */
    fun classifySource(relativePath: String?, absolutePath: String?): String? {
        val normRel = (relativePath ?: "")
            .replace('\\', '/')
            .trim('/')
            .lowercase()

        if (normRel == "dcim/camera" || normRel.startsWith("dcim/camera/")) {
            return "camera"
        }
        if (
            normRel == "dcim/screenshots" ||
            normRel.startsWith("dcim/screenshots/") ||
            normRel == "pictures/screenshots" ||
            normRel.startsWith("pictures/screenshots/")
        ) {
            return "screenshots"
        }

        val normAbs = (absolutePath ?: "").replace('\\', '/').lowercase()
        if (normAbs.contains("/dcim/camera/")) {
            return "camera"
        }
        if (normAbs.contains("/dcim/screenshots/") || normAbs.contains("/pictures/screenshots/")) {
            return "screenshots"
        }

        return null
    }

    fun discover(
        context: Context,
        includeCamera: Boolean = true,
        includeScreenshots: Boolean = true,
    ): List<DiscoveredMediaItem> {
        val results = mutableListOf<DiscoveredMediaItem>()
        if (!includeCamera && !includeScreenshots) return results

        queryCollection(
            context = context,
            collectionUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            isVideo = false,
            includeCamera = includeCamera,
            includeScreenshots = includeScreenshots,
            out = results,
        )
        queryCollection(
            context = context,
            collectionUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            isVideo = true,
            includeCamera = includeCamera,
            includeScreenshots = includeScreenshots,
            out = results,
        )

        // Sort oldest-first chronologically, tie-breaking deterministically by filename and id.
        results.sortWith(
            compareBy<DiscoveredMediaItem> { it.createdAtMs }
                .thenBy { it.fileName }
                .thenBy { it.id },
        )
        return results
    }

    fun getSourceCounts(context: Context): Map<String, Int> {
        val all = discover(context, includeCamera = true, includeScreenshots = true)
        var cameraCount = 0
        var screenshotsCount = 0
        for (item in all) {
            when (item.sourceFolder) {
                "camera" -> cameraCount++
                "screenshots" -> screenshotsCount++
            }
        }
        return mapOf(
            "camera" to cameraCount,
            "screenshots" to screenshotsCount,
        )
    }

    private fun queryCollection(
        context: Context,
        collectionUri: Uri,
        isVideo: Boolean,
        includeCamera: Boolean,
        includeScreenshots: Boolean,
        out: MutableList<DiscoveredMediaItem>,
    ) {
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
            projection.add(MediaStore.MediaColumns.DATE_TAKEN)
            projection.add(MediaStore.MediaColumns.IS_PENDING)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            projection.add(MediaStore.MediaColumns.IS_TRASHED)
        }

        val selectionParts = mutableListOf("${MediaStore.MediaColumns.SIZE} > 0")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selectionParts.add("${MediaStore.MediaColumns.IS_PENDING} = 0")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            selectionParts.add("${MediaStore.MediaColumns.IS_TRASHED} = 0")
        }
        val selection = selectionParts.joinToString(" AND ")

        context.contentResolver.query(
            collectionUri,
            projection.toTypedArray(),
            selection,
            null,
            null,
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val dataIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val modIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val mimeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val relIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            } else {
                -1
            }
            val takenIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val idLong = cursor.getLong(idIdx)
                val localPath = if (dataIdx >= 0) cursor.getString(dataIdx) else null
                val relPath = if (relIdx >= 0) cursor.getString(relIdx) else null

                val source = classifySource(relPath, localPath) ?: continue
                if (source == "camera" && !includeCamera) continue
                if (source == "screenshots" && !includeScreenshots) continue
                if (localPath.isNullOrBlank()) continue

                val file = File(localPath)
                if (!file.exists() || !file.isFile) continue

                val fileName = cursor.getString(nameIdx) ?: file.name
                val sizeBytes = cursor.getLong(sizeIdx).takeIf { it > 0L } ?: file.length()
                if (sizeBytes <= 0L) continue

                val dateTaken = if (takenIdx >= 0 && !cursor.isNull(takenIdx)) {
                    cursor.getLong(takenIdx)
                } else {
                    0L
                }
                val dateModMs = cursor.getLong(modIdx) * 1000L
                val fileModMs = file.lastModified()
                val createdAtMs = when {
                    dateTaken > 0L -> dateTaken
                    dateModMs > 0L -> dateModMs
                    fileModMs > 0L -> fileModMs
                    else -> System.currentTimeMillis()
                }

                val mime = (if (mimeIdx >= 0) cursor.getString(mimeIdx) else null)
                    ?: if (isVideo) "video/*" else "image/*"

                val contentUri = ContentUris.withAppendedId(collectionUri, idLong).toString()
                val uniqueId = "${if (isVideo) "vid" else "img"}_$idLong"

                out.add(
                    DiscoveredMediaItem(
                        id = uniqueId,
                        contentUri = contentUri,
                        fileName = fileName,
                        localPath = localPath,
                        sourceFolder = source,
                        sizeBytes = sizeBytes,
                        createdAtMs = createdAtMs,
                        mimeType = mime,
                    ),
                )
            }
        }
    }
}
