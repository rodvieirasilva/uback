package uback.rodvieirasilva.github.io

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.os.Environment
import android.util.Log
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Persists per-scope WhatsApp incremental delta watermarks (`lastExportedRowId`).
 * Watermarks MUST ONLY be advanced strictly after the delta SQLite file passes
 * SMB SHA-256 read-back verification.
 */
object WhatsAppDeltaState {
    private const val PREFS_NAME = "uback_wa_delta_state"

    fun getWatermark(context: Context, scope: String): Long {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getLong("last_row_id_$scope", 0L)
    }

    fun commitWatermark(context: Context, scope: String, maxRowId: Long) {
        if (scope.isBlank() || maxRowId <= 0L) return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val current = prefs.getLong("last_row_id_$scope", 0L)
        if (maxRowId > current) {
            prefs.edit().putLong("last_row_id_$scope", maxRowId).apply()
            Log.i("UBack", "Committed WhatsApp delta watermark for $scope -> _id=$maxRowId")
        }
    }
}

/**
 * Decrypts local WhatsApp `.crypt15` databases on-device (using the user's 64-digit key) and
 * exports ONLY new messages (`_id > watermark`) plus referenced `chat`, `jid`, and `message_media`
 * rows into a self-contained incremental SQLite delta file (`msgstore_delta_*.db`).
 *
 * Guarantees:
 * - Zero duplication of previously backed-up messages.
 * - Deleted messages stay safely preserved in earlier delta `.db` files on the NAS.
 * - Full decrypted DB is always wiped from app cache immediately after delta extraction.
 */
object WhatsAppDeltaExporter {

    private const val TAG = "UBack"
    private val dateFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

    private data class ScopeSpec(
        val scope: String,
        val sourceId: String,
        val remoteSubpath: String,
        val candidateDirs: List<String>,
    )

    private val SCOPES = listOf(
        ScopeSpec(
            scope = "whatsapp",
            sourceId = "whatsapp.deltas",
            remoteSubpath = "whatsapp/deltas",
            candidateDirs = listOf(
                "Android/media/com.whatsapp/WhatsApp/Databases",
                "WhatsApp/Databases",
            ),
        ),
        ScopeSpec(
            scope = "whatsapp_business",
            sourceId = "whatsapp_business.deltas",
            remoteSubpath = "whatsapp-business/deltas",
            candidateDirs = listOf(
                "Android/media/com.whatsapp.w4b/WhatsApp Business/Databases",
            ),
        ),
    )

    fun estimateStats(
        context: Context,
        whatsappKey: String?,
    ): Map<String, Map<String, Any>> {
        val validKey = WhatsAppCrypt15Decryptor.normalizeHexKey(whatsappKey) != null
        val out = mutableMapOf<String, Map<String, Any>>()
        for (spec in SCOPES) {
            val latest = findLatestCrypt15(spec)
            out[spec.sourceId] = when {
                latest == null -> mapOf("count" to 0, "totalBytes" to 0L)
                !validKey -> mapOf(
                    "count" to 0,
                    "totalBytes" to 0L,
                    "statusNote" to "Set 64-digit key in Settings",
                )
                else -> {
                    val estBytes = maxOf(4096L, latest.length() / 10L)
                    mapOf("count" to 1, "totalBytes" to estBytes)
                }
            }
        }
        return out
    }

    fun exportEnabledDeltas(
        context: Context,
        enabledSources: Set<String>,
        whatsappKey: String?,
    ): List<DiscoveredMediaItem> {
        val normKey = WhatsAppCrypt15Decryptor.normalizeHexKey(whatsappKey) ?: return emptyList()
        val out = mutableListOf<DiscoveredMediaItem>()
        for (spec in SCOPES) {
            if (spec.sourceId !in enabledSources) continue
            runCatching { exportScopeDelta(context, spec, normKey) }
                .onFailure { Log.w(TAG, "WhatsApp delta export failed for ${spec.scope}: ${it.message}") }
                .getOrNull()?.let { out.add(it) }
        }
        return out
    }

    private fun findLatestCrypt15(spec: ScopeSpec): File? {
        val root = Environment.getExternalStorageDirectory()
        val candidates = mutableListOf<File>()
        for (rel in spec.candidateDirs) {
            val dir = File(root, rel)
            if (!dir.exists() || !dir.isDirectory) continue
            val files = dir.listFiles { f ->
                f.isFile && f.length() > 48L && f.name.endsWith(".crypt15", ignoreCase = true) &&
                    f.name.startsWith("msgstore", ignoreCase = true)
            } ?: continue
            candidates.addAll(files)
        }
        if (candidates.isEmpty()) return null
        // Prefer canonical `msgstore.db.crypt15` when present, else newest dated backup.
        candidates.firstOrNull { it.name.equals("msgstore.db.crypt15", ignoreCase = true) }?.let { return it }
        return candidates.maxByOrNull { it.lastModified() }
    }

    private fun exportScopeDelta(
        context: Context,
        spec: ScopeSpec,
        normKey64: String,
    ): DiscoveredMediaItem? {
        val cryptFile = findLatestCrypt15(spec) ?: return null
        val cacheDir = File(context.cacheDir, "uback_wa_delta").apply { mkdirs() }
        val decryptedFile = File(cacheDir, "${spec.scope}_decrypted_${System.currentTimeMillis()}.db")

        try {
            WhatsAppCrypt15Decryptor.decryptToSqliteFile(cryptFile, normKey64, decryptedFile)
            return buildDeltaDatabase(context, spec, cryptFile, decryptedFile, cacheDir)
        } finally {
            // Always remove full decrypted DB immediately after extracting the delta!
            runCatching { decryptedFile.delete() }
            runCatching { File("${decryptedFile.absolutePath}-wal").delete() }
            runCatching { File("${decryptedFile.absolutePath}-shm").delete() }
        }
    }

    private fun buildDeltaDatabase(
        context: Context,
        spec: ScopeSpec,
        cryptFile: File,
        decryptedFile: File,
        cacheDir: File,
    ): DiscoveredMediaItem? {
        val watermark = WhatsAppDeltaState.getWatermark(context, spec.scope)
        val srcDb = SQLiteDatabase.openDatabase(
            decryptedFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READONLY,
        )
        try {
            val msgTable = when {
                tableExists(srcDb, "message") -> "message"
                tableExists(srcDb, "messages") -> "messages"
                else -> {
                    Log.w(TAG, "No WhatsApp message/messages table found in ${cryptFile.name}")
                    return null
                }
            }

            var minRowId = 0L
            var maxRowId = 0L
            var newCount = 0L
            srcDb.rawQuery(
                "SELECT MIN(_id), MAX(_id), COUNT(*) FROM $msgTable WHERE _id > ?",
                arrayOf(watermark.toString()),
            ).use { c ->
                if (c.moveToFirst()) {
                    minRowId = if (c.isNull(0)) 0L else c.getLong(0)
                    maxRowId = if (c.isNull(1)) 0L else c.getLong(1)
                    newCount = c.getLong(2)
                }
            }

            if (newCount <= 0L || maxRowId <= watermark) {
                Log.i(TAG, "WhatsApp delta (${spec.scope}): 0 new messages since _id=$watermark (skipped)")
                return null
            }

            val stamp = LocalDate.now().format(dateFmt)
            val deltaFile = File(cacheDir, "msgstore_delta_${stamp}_${minRowId}_${maxRowId}.db")
            runCatching { deltaFile.delete() }

            val dstDb = SQLiteDatabase.openOrCreateDatabase(deltaFile, null)
            try {
                dstDb.rawQuery("PRAGMA journal_mode=DELETE", null).use { }
                dstDb.beginTransaction()
                try {
                    dstDb.execSQL(
                        """
                        CREATE TABLE delta_meta (
                            scope TEXT NOT NULL,
                            source_file TEXT NOT NULL,
                            exported_at_ms INTEGER NOT NULL,
                            from_row_id INTEGER NOT NULL,
                            to_row_id INTEGER NOT NULL,
                            message_count INTEGER NOT NULL,
                            message_table TEXT NOT NULL
                        )
                        """.trimIndent(),
                    )
                    val nowMs = System.currentTimeMillis()
                    dstDb.execSQL(
                        "INSERT INTO delta_meta VALUES (?, ?, ?, ?, ?, ?, ?)",
                        arrayOf<Any>(spec.scope, cryptFile.name, nowMs, minRowId, maxRowId, newCount, msgTable),
                    )

                    // Copy new message rows
                    copyTableSubset(
                        srcDb = srcDb,
                        dstDb = dstDb,
                        tableName = msgTable,
                        whereClause = "_id > ?",
                        whereArgs = arrayOf(watermark.toString()),
                    )

                    // Copy referenced context tables so every delta is standalone & queryable
                    if (msgTable == "message") {
                        if (tableExists(srcDb, "chat")) {
                            val chatCols = getColumnNames(srcDb, "message")
                            if ("chat_row_id" in chatCols) {
                                copyTableSubset(
                                    srcDb = srcDb,
                                    dstDb = dstDb,
                                    tableName = "chat",
                                    whereClause = "_id IN (SELECT DISTINCT chat_row_id FROM message WHERE _id > ? AND chat_row_id IS NOT NULL)",
                                    whereArgs = arrayOf(watermark.toString()),
                                )
                            }
                        }
                        if (tableExists(srcDb, "jid")) {
                            val jidFilters = mutableListOf<String>()
                            val args = mutableListOf<String>()
                            val msgCols = getColumnNames(srcDb, "message")
                            if ("sender_jid_row_id" in msgCols) {
                                jidFilters.add("_id IN (SELECT DISTINCT sender_jid_row_id FROM message WHERE _id > ? AND sender_jid_row_id IS NOT NULL)")
                                args.add(watermark.toString())
                            }
                            if (tableExists(srcDb, "chat") && "chat_row_id" in msgCols && "jid_row_id" in getColumnNames(srcDb, "chat")) {
                                jidFilters.add("_id IN (SELECT DISTINCT c.jid_row_id FROM chat c JOIN message m ON m.chat_row_id = c._id WHERE m._id > ? AND c.jid_row_id IS NOT NULL)")
                                args.add(watermark.toString())
                            }
                            if (jidFilters.isNotEmpty()) {
                                copyTableSubset(
                                    srcDb = srcDb,
                                    dstDb = dstDb,
                                    tableName = "jid",
                                    whereClause = jidFilters.joinToString(" OR "),
                                    whereArgs = args.toTypedArray(),
                                )
                            }
                        }
                        if (tableExists(srcDb, "message_media") && "message_row_id" in getColumnNames(srcDb, "message_media")) {
                            copyTableSubset(
                                srcDb = srcDb,
                                dstDb = dstDb,
                                tableName = "message_media",
                                whereClause = "message_row_id > ?",
                                whereArgs = arrayOf(watermark.toString()),
                            )
                        }
                    }

                    dstDb.setTransactionSuccessful()
                } finally {
                    dstDb.endTransaction()
                }
            } finally {
                dstDb.close()
                runCatching { File("${deltaFile.absolutePath}-journal").delete() }
            }

            if (!deltaFile.exists() || deltaFile.length() <= 0L) return null
            Log.i(
                TAG,
                "Exported WhatsApp SQLite delta (${spec.scope}): ${deltaFile.name} " +
                    "($newCount new messages, _id $minRowId..$maxRowId, ${deltaFile.length()} bytes)",
            )
            return DiscoveredMediaItem(
                id = "wa_delta_${spec.scope}_${minRowId}_${maxRowId}",
                contentUri = null,
                fileName = deltaFile.name,
                localPath = deltaFile.absolutePath,
                sourceId = spec.sourceId,
                sourceFolder = spec.remoteSubpath,
                sizeBytes = deltaFile.length(),
                createdAtMs = System.currentTimeMillis(),
                mimeType = "application/vnd.sqlite3",
                isSnapshot = true,
                isReadOnly = true,
                deltaScope = spec.scope,
                deltaMaxRowId = maxRowId,
            )
        } finally {
            srcDb.close()
        }
    }

    private fun copyTableSubset(
        srcDb: SQLiteDatabase,
        dstDb: SQLiteDatabase,
        tableName: String,
        whereClause: String,
        whereArgs: Array<String>,
    ) {
        val ddl = getCreateTableSql(srcDb, tableName) ?: return
        dstDb.execSQL(ddl)
        val cols = getColumnNames(srcDb, tableName)
        if (cols.isEmpty()) return

        val quotedCols = cols.joinToString(", ") { "\"$it\"" }
        val placeholders = cols.joinToString(", ") { "?" }
        val insertStmt = dstDb.compileStatement(
            "INSERT OR IGNORE INTO \"$tableName\" ($quotedCols) VALUES ($placeholders)",
        )
        try {
            srcDb.rawQuery(
                "SELECT $quotedCols FROM \"$tableName\" WHERE $whereClause",
                whereArgs,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    insertStmt.clearBindings()
                    for (i in cols.indices) {
                        val bindIdx = i + 1
                        when (cursor.getType(i)) {
                            Cursor.FIELD_TYPE_NULL -> insertStmt.bindNull(bindIdx)
                            Cursor.FIELD_TYPE_INTEGER -> insertStmt.bindLong(bindIdx, cursor.getLong(i))
                            Cursor.FIELD_TYPE_FLOAT -> insertStmt.bindDouble(bindIdx, cursor.getDouble(i))
                            Cursor.FIELD_TYPE_STRING -> insertStmt.bindString(bindIdx, cursor.getString(i))
                            Cursor.FIELD_TYPE_BLOB -> insertStmt.bindBlob(bindIdx, cursor.getBlob(i))
                        }
                    }
                    insertStmt.executeInsert()
                }
            }
        } finally {
            insertStmt.close()
        }
    }

    private fun tableExists(db: SQLiteDatabase, name: String): Boolean {
        db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
            arrayOf(name),
        ).use { return it.moveToFirst() }
    }

    private fun getCreateTableSql(db: SQLiteDatabase, name: String): String? {
        db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
            arrayOf(name),
        ).use { c ->
            return if (c.moveToFirst()) c.getString(0) else null
        }
    }

    private fun getColumnNames(db: SQLiteDatabase, tableName: String): List<String> {
        val out = mutableListOf<String>()
        db.rawQuery("PRAGMA table_info(\"$tableName\")", null).use { c ->
            val nameIdx = c.getColumnIndex("name")
            while (c.moveToNext()) {
                if (nameIdx >= 0) {
                    c.getString(nameIdx)?.let { out.add(it) }
                }
            }
        }
        return out
    }
}
