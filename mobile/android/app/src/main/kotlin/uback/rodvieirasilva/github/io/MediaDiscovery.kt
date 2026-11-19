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
    val contentUri: String?,
    val fileName: String,
    val localPath: String,
    val sourceId: String,
    val sourceFolder: String,
    val sizeBytes: Long,
    val createdAtMs: Long,
    val mimeType: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "contentUri" to contentUri,
        "fileName" to fileName,
        "localPath" to localPath,
        "sourceId" to sourceId,
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
        if (!globalName.isNullOrBlank()) return globalName.trim()

        val secureName = runCatching {
            Settings.Secure.getString(context.contentResolver, "bluetooth_name")
        }.getOrNull()
        if (!secureName.isNullOrBlank()) return secureName.trim()

        return Build.MODEL ?: "android"
    }

    /**
     * Discovers items across [enabledSources]. When [perSourceLimit] is provided (e.g. for an
     * "oldest N files" batch), keeps at most [perSourceLimit] oldest candidates per source first
     * and then merges & sorts globally oldest-first across ALL enabled sources.
     */
    fun discover(
        context: Context,
        enabledSources: Set<String> = MediaSourceClassifier.ALL_SOURCE_IDS,
        perSourceLimit: Int? = null,
    ): List<DiscoveredMediaItem> {
        if (enabledSources.isEmpty()) return emptyList()

        val seenPaths = HashSet<String>()
        val collected = mutableListOf<DiscoveredMediaItem>()

        queryCollection(
            context = context,
            collectionUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            mediaKind = "image",
            enabledSources = enabledSources,
            seenPaths = seenPaths,
            out = collected,
        )
        queryCollection(
            context = context,
            collectionUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            mediaKind = "video",
            enabledSources = enabledSources,
            seenPaths = seenPaths,
            out = collected,
        )
        queryCollection(
            context = context,
            collectionUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            mediaKind = "audio",
            enabledSources = enabledSources,
            seenPaths = seenPaths,
            out = collected,
        )

        // Direct filesystem pass for WhatsApp Sent / Voice Notes (.nomedia) & Recordings.
        scanDirectRoots(enabledSources, seenPaths, collected)

        val comparator = compareBy<DiscoveredMediaItem> { it.createdAtMs }
            .thenBy { it.fileName }
            .thenBy { it.id }

        if (perSourceLimit != null && perSourceLimit > 0) {
            val capped = collected
                .groupBy { it.sourceId }
                .values
                .flatMap { list -> list.sortedWith(comparator).take(perSourceLimit) }
            return capped.sortedWith(comparator)
        }

        collected.sortWith(comparator)
        return collected
    }

    /**
     * Fast aggregate stats (count + totalBytes) per leaf source ID across MediaStore
     * and direct WhatsApp/Recordings folders.
     */
    fun getSourceStats(context: Context): Map<String, Map<String, Any>> {
        val counts = mutableMapOf<String, Int>()
        val bytes = mutableMapOf<String, Long>()
        for (id in MediaSourceClassifier.ALL_SOURCE_IDS) {
            counts[id] = 0
            bytes[id] = 0L
        }

        val seenPaths = HashSet<String>()
        accumulateMediaStoreStats(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image", seenPaths, counts, bytes)
        accumulateMediaStoreStats(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "video", seenPaths, counts, bytes)
        accumulateMediaStoreStats(context, MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, "audio", seenPaths, counts, bytes)
        accumulateDirectStats(seenPaths, counts, bytes)

        return MediaSourceClassifier.ALL_SOURCE_IDS.associateWith { id ->
            mapOf(
                "count" to (counts[id] ?: 0),
                "totalBytes" to (bytes[id] ?: 0L),
            )
        }
    }

    private fun accumulateMediaStoreStats(
        context: Context,
        collectionUri: Uri,
        mediaKind: String,
        seenPaths: HashSet<String>,
        counts: MutableMap<String, Int>,
        bytes: MutableMap<String, Long>,
    ) {
        val projection = mutableListOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.SIZE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.RELATIVE_PATH)
        }

        context.contentResolver.query(
            collectionUri,
            projection.toTypedArray(),
            buildActiveSelection(),
            null,
            null,
        )?.use { cursor ->
            val dataIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val relIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val localPath = if (dataIdx >= 0) cursor.getString(dataIdx) else null
                val relPath = if (relIdx >= 0) cursor.getString(relIdx) else null
                val classified = MediaSourceClassifier.classify(relPath, localPath, mediaKind) ?: continue
                val size = cursor.getLong(sizeIdx)
                if (size <= 0L) continue
                if (!localPath.isNullOrBlank()) {
                    val key = canonicalKey(localPath)
                    if (!seenPaths.add(key)) continue
                }
                counts[classified.sourceId] = (counts[classified.sourceId] ?: 0) + 1
                bytes[classified.sourceId] = (bytes[classified.sourceId] ?: 0L) + size
            }
        }
    }

    private fun accumulateDirectStats(
        seenPaths: HashSet<String>,
        counts: MutableMap<String, Int>,
        bytes: MutableMap<String, Long>,
    ) {
        for (root in MediaSourceClassifier.directScanRoots()) {
            walkFiles(root) { file ->
                val kind = MediaSourceClassifier.mediaKindFromPath(file.name, null) ?: return@walkFiles
                val classified = MediaSourceClassifier.classify(null, file.absolutePath, kind) ?: return@walkFiles
                val size = file.length()
                if (size <= 0L) return@walkFiles
                val key = canonicalKey(file.absolutePath)
                if (!seenPaths.add(key)) return@walkFiles
                counts[classified.sourceId] = (counts[classified.sourceId] ?: 0) + 1
                bytes[classified.sourceId] = (bytes[classified.sourceId] ?: 0L) + size
            }
        }
    }

    private fun scanDirectRoots(
        enabledSources: Set<String>,
        seenPaths: HashSet<String>,
        out: MutableList<DiscoveredMediaItem>,
    ) {
        for (root in MediaSourceClassifier.directScanRoots()) {
            walkFiles(root) { file ->
                val kind = MediaSourceClassifier.mediaKindFromPath(file.name, null) ?: return@walkFiles
                val classified = MediaSourceClassifier.classify(null, file.absolutePath, kind) ?: return@walkFiles
                if (!enabledSources.contains(classified.sourceId)) return@walkFiles
                val size = file.length()
                if (size <= 0L) return@walkFiles
                val key = canonicalKey(file.absolutePath)
                if (!seenPaths.add(key)) return@walkFiles

                val createdAtMs = file.lastModified().takeIf { it > 0L } ?: System.currentTimeMillis()
                out.add(
                    DiscoveredMediaItem(
                        id = "fs_${key.hashCode()}",
                        contentUri = null,
                        fileName = file.name,
                        localPath = file.absolutePath,
                        sourceId = classified.sourceId,
                        sourceFolder = classified.remoteSubpath,
                        sizeBytes = size,
                        createdAtMs = createdAtMs,
                        mimeType = MediaSourceClassifier.mimeTypeFor(file.name, kind),
                    ),
                )
            }
        }
    }

    private fun walkFiles(dir: File, onFile: (File) -> Unit) {
        val children = dir.listFiles() ?: return
        for (child in children) {
            if (child.name.startsWith(".")) continue
            if (child.isDirectory) {
                walkFiles(child, onFile)
            } else if (child.isFile) {
                onFile(child)
            }
        }
    }

    private fun buildActiveSelection(): String {
        val selectionParts = mutableListOf("${MediaStore.MediaColumns.SIZE} > 0")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selectionParts.add("${MediaStore.MediaColumns.IS_PENDING} = 0")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            selectionParts.add("${MediaStore.MediaColumns.IS_TRASHED} = 0")
        }
        return selectionParts.joinToString(" AND ")
    }

    private fun queryCollection(
        context: Context,
        collectionUri: Uri,
        mediaKind: String,
        enabledSources: Set<String>,
        seenPaths: HashSet<String>,
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

        context.contentResolver.query(
            collectionUri,
            projection.toTypedArray(),
            buildActiveSelection(),
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

                val classified = MediaSourceClassifier.classify(relPath, localPath, mediaKind) ?: continue
                if (!enabledSources.contains(classified.sourceId)) continue
                if (localPath.isNullOrBlank()) continue

                val file = File(localPath)
                if (!file.exists() || !file.isFile) continue
                val key = canonicalKey(file.absolutePath)
                if (!seenPaths.add(key)) continue

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
                    ?: MediaSourceClassifier.mimeTypeFor(fileName, mediaKind)

                val contentUri = ContentUris.withAppendedId(collectionUri, idLong).toString()
                val uniqueId = "${mediaKind}_$idLong"

                out.add(
                    DiscoveredMediaItem(
                        id = uniqueId,
                        contentUri = contentUri,
                        fileName = fileName,
                        localPath = file.absolutePath,
                        sourceId = classified.sourceId,
                        sourceFolder = classified.remoteSubpath,
                        sizeBytes = sizeBytes,
                        createdAtMs = createdAtMs,
                        mimeType = mime,
                    ),
                )
            }
        }
    }

    private fun canonicalKey(path: String): String =
        runCatching { File(path).canonicalPath }.getOrDefault(path)
}
