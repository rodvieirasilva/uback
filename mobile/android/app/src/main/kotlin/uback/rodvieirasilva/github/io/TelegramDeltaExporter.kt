package uback.rodvieirasilva.github.io

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.drinkless.tdlib.TdApi
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Exports full-history & incremental Telegram chat data (`message_id > watermark` per chat)
 * into a self-contained SQLite `.db` file (`PRAGMA journal_mode=DELETE`) using an authenticated
 * [TelegramClientManager] session.
 *
 * Includes:
 * - All Main and Archived chats (`LoadChats` loop + `GetChats`)
 * - Full message history per chat on initial backfill (no 1,000-message cap) and incremental
 *   deltas on subsequent runs
 * - `users`, `chats`, and `messages` tables with full metadata (replies, forwards, edits,
 *   outgoing flag, media attributes, stickers, polls, contacts, locations, calls, web pages)
 */
object TelegramDeltaExporter {
    private const val TAG = "UBack"
    private const val PREFS_NAME = "uback_telegram_delta_state"
    private const val KEY_SCHEMA_VERSION = "schema_version"
    private const val CURRENT_SCHEMA_VERSION = 2
    private const val KEY_WATERMARKS_PREFIX = "chat_wm_"
    private const val MAX_CHATS_QUERY = 10_000
    private const val PAGE_SIZE = 100
    private const val REMOTE_SUBPATH = "telegram/deltas"

    private val pendingWatermarks = ConcurrentHashMap<String, Map<Long, Long>>()

    private fun ensureSchemaVersion(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val version = prefs.getInt(KEY_SCHEMA_VERSION, 0)
        if (version < CURRENT_SCHEMA_VERSION) {
            // Reset legacy partial v1 watermarks once so full-history v2 backfill runs cleanly.
            prefs.edit().clear().putInt(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION).apply()
            Log.i(TAG, "Telegram delta: upgraded state schema $version -> $CURRENT_SCHEMA_VERSION (full backfill enabled)")
        }
    }

    private fun loadAllChatIds(): List<Pair<Long, Boolean>> {
        val seen = LinkedHashSet<Long>()
        val result = mutableListOf<Pair<Long, Boolean>>()
        val lists = listOf(
            TdApi.ChatListMain() to false,
            TdApi.ChatListArchive() to true,
        )
        for ((chatList, isArchived) in lists) {
            // Repeatedly invoke LoadChats until TDLib reports 404 (all chats loaded).
            for (attempt in 0 until 50) {
                val res = TelegramClientManager.query(TdApi.LoadChats(chatList, 500))
                if (res is TdApi.Error || res == null) break
            }
            val chatsObj = TelegramClientManager.query(TdApi.GetChats(chatList, MAX_CHATS_QUERY))
            if (chatsObj is TdApi.Chats) {
                for (id in chatsObj.chatIds) {
                    if (seen.add(id)) {
                        result.add(id to isArchived)
                    }
                }
            }
        }
        return result
    }

    fun estimateStats(context: Context): Map<String, Map<String, Any>> {
        ensureSchemaVersion(context)
        TelegramClientManager.ensureInitializedFromPrefs(context)
        val state = TelegramClientManager.getAuthState()["state"] as? String
        if (state != "ready") {
            return mapOf("telegram.deltas" to mapOf("count" to 0, "totalBytes" to 0L))
        }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val chatPairs = loadAllChatIds()
        var chatsWithNew = 0
        for ((chatId, _) in chatPairs) {
            val chatObj = TelegramClientManager.query(TdApi.GetChat(chatId)) as? TdApi.Chat ?: continue
            val lastMsgId = chatObj.lastMessage?.id ?: 0L
            val wm = prefs.getLong("$KEY_WATERMARKS_PREFIX$chatId", 0L)
            if (lastMsgId > wm) {
                chatsWithNew++
            }
        }
        return if (chatsWithNew > 0) {
            mapOf("telegram.deltas" to mapOf("count" to 1, "totalBytes" to chatsWithNew * 8192L))
        } else {
            mapOf("telegram.deltas" to mapOf("count" to 0, "totalBytes" to 0L))
        }
    }

    fun exportEnabledDeltas(
        context: Context,
        enabledSources: Set<String>,
    ): List<DiscoveredMediaItem> {
        if ("telegram.deltas" !in enabledSources) return emptyList()
        ensureSchemaVersion(context)
        TelegramClientManager.ensureInitializedFromPrefs(context)
        val state = TelegramClientManager.getAuthState()["state"] as? String
        if (state != "ready") {
            Log.i(TAG, "Telegram delta: not authenticated (state=$state, skipped)")
            return emptyList()
        }

        val chatPairs = loadAllChatIds()
        if (chatPairs.isEmpty()) {
            Log.i(TAG, "Telegram delta: 0 chats returned (skipped)")
            return emptyList()
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val newWatermarks = mutableMapOf<Long, Long>()
        val exportedChats = mutableListOf<ChatRow>()
        val exportedMessages = mutableListOf<MessageRow>()
        val referencedUserIds = LinkedHashSet<Long>()

        for ((chatId, isArchived) in chatPairs) {
            val chat = TelegramClientManager.query(TdApi.GetChat(chatId)) as? TdApi.Chat ?: continue
            val wm = prefs.getLong("$KEY_WATERMARKS_PREFIX$chatId", 0L)
            val lastMsgId = chat.lastMessage?.id ?: 0L
            if (lastMsgId <= wm) continue

            val chatType = chat.type
            if (chatType is TdApi.ChatTypePrivate) {
                referencedUserIds.add(chatType.userId)
            }
            exportedChats.add(
                ChatRow(
                    id = chatId,
                    title = chat.title ?: "",
                    type = chatType.javaClass.simpleName,
                    isArchived = isArchived,
                    unreadCount = chat.unreadCount,
                    lastReadInboxId = chat.lastReadInboxMessageId,
                    lastReadOutboxId = chat.lastReadOutboxMessageId,
                ),
            )

            var fromMsgId = 0L
            var maxSeenId = wm
            var consecutiveEmpty = 0
            while (true) {
                val history = TelegramClientManager.query(
                    TdApi.GetChatHistory(chatId, fromMsgId, 0, PAGE_SIZE, false),
                ) as? TdApi.Messages ?: break
                val msgs = history.messages
                if (msgs.isEmpty()) {
                    consecutiveEmpty++
                    if (consecutiveEmpty >= 2) break
                    continue
                }
                consecutiveEmpty = 0

                var reachedWatermark = false
                for (msg in msgs) {
                    if (msg.id <= wm) {
                        reachedWatermark = true
                        break
                    }
                    if (msg.id > maxSeenId) maxSeenId = msg.id
                    val sender = msg.senderId
                    if (sender is TdApi.MessageSenderUser) {
                        referencedUserIds.add(sender.userId)
                    }
                    exportedMessages.add(extractMessageRow(chatId, msg))
                }
                val oldestInPage = msgs.last().id
                if (reachedWatermark || oldestInPage == fromMsgId) break
                fromMsgId = oldestInPage
            }
            if (maxSeenId > wm) {
                newWatermarks[chatId] = maxSeenId
            }
        }

        if (exportedMessages.isEmpty()) {
            Log.i(TAG, "Telegram delta: 0 new messages across ${chatPairs.size} chats (skipped)")
            return emptyList()
        }

        val exportedUsers = mutableListOf<UserRow>()
        for (uid in referencedUserIds) {
            val user = TelegramClientManager.query(TdApi.GetUser(uid)) as? TdApi.User ?: continue
            val username = user.usernames?.editableUsername
                ?: user.usernames?.activeUsernames?.firstOrNull()
                ?: ""
            exportedUsers.add(
                UserRow(
                    id = user.id,
                    firstName = user.firstName ?: "",
                    lastName = user.lastName ?: "",
                    username = username,
                    phoneNumber = user.phoneNumber ?: "",
                    isContact = user.isContact,
                    type = user.type?.javaClass?.simpleName ?: "",
                ),
            )
        }

        val nowMs = System.currentTimeMillis()
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date(nowMs))
        val outFile = File(context.cacheDir, "telegram_delta_$stamp.db")
        if (outFile.exists()) outFile.delete()

        writeDeltaDatabase(outFile, exportedUsers, exportedChats, exportedMessages)

        val itemId = "telegram_delta_$stamp"
        pendingWatermarks[itemId] = newWatermarks
        Log.i(
            TAG,
            "Telegram delta: exported ${exportedMessages.size} messages, ${exportedChats.size} chats, " +
                "${exportedUsers.size} users -> ${outFile.name} (${outFile.length()} bytes)",
        )

        return listOf(
            DiscoveredMediaItem(
                id = itemId,
                contentUri = null,
                fileName = outFile.name,
                localPath = outFile.absolutePath,
                sourceId = "telegram.deltas",
                sourceFolder = REMOTE_SUBPATH,
                sizeBytes = outFile.length(),
                createdAtMs = nowMs,
                mimeType = "application/vnd.sqlite3",
                isSnapshot = true,
                isReadOnly = true,
            ),
        )
    }

    fun commitWatermark(context: Context, itemId: String) {
        val updates = pendingWatermarks.remove(itemId) ?: return
        val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
        editor.putInt(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION)
        for ((chatId, msgId) in updates) {
            editor.putLong("$KEY_WATERMARKS_PREFIX$chatId", msgId)
        }
        editor.apply()
        Log.i(TAG, "Telegram delta: committed watermarks for ${updates.size} chats ($itemId)")
    }

    private fun writeDeltaDatabase(
        outFile: File,
        users: List<UserRow>,
        chats: List<ChatRow>,
        messages: List<MessageRow>,
    ) {
        val db = SQLiteDatabase.openOrCreateDatabase(outFile, null)
        try {
            db.rawQuery("PRAGMA journal_mode=DELETE", null).use { }
            db.beginTransaction()
            try {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        id INTEGER PRIMARY KEY,
                        first_name TEXT,
                        last_name TEXT,
                        username TEXT,
                        phone_number TEXT,
                        is_contact INTEGER,
                        type TEXT
                    )
                    """.trimIndent(),
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS chats (
                        id INTEGER PRIMARY KEY,
                        title TEXT,
                        type TEXT,
                        is_archived INTEGER,
                        unread_count INTEGER,
                        last_read_inbox_id INTEGER,
                        last_read_outbox_id INTEGER
                    )
                    """.trimIndent(),
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS messages (
                        id INTEGER,
                        chat_id INTEGER,
                        sender_id TEXT,
                        date INTEGER,
                        edit_date INTEGER,
                        is_outgoing INTEGER,
                        reply_to_message_id INTEGER,
                        media_album_id INTEGER,
                        forward_info TEXT,
                        content_type TEXT,
                        text TEXT,
                        media_file_name TEXT,
                        media_mime_type TEXT,
                        media_size INTEGER,
                        media_duration INTEGER,
                        media_width INTEGER,
                        media_height INTEGER,
                        extra_json TEXT,
                        PRIMARY KEY (chat_id, id)
                    )
                    """.trimIndent(),
                )

                val userStmt = db.compileStatement(
                    "INSERT OR REPLACE INTO users (id, first_name, last_name, username, phone_number, is_contact, type) VALUES (?, ?, ?, ?, ?, ?, ?)",
                )
                for (u in users) {
                    userStmt.bindLong(1, u.id)
                    userStmt.bindString(2, u.firstName)
                    userStmt.bindString(3, u.lastName)
                    userStmt.bindString(4, u.username)
                    userStmt.bindString(5, u.phoneNumber)
                    userStmt.bindLong(6, if (u.isContact) 1L else 0L)
                    userStmt.bindString(7, u.type)
                    userStmt.executeInsert()
                }

                val chatStmt = db.compileStatement(
                    "INSERT OR REPLACE INTO chats (id, title, type, is_archived, unread_count, last_read_inbox_id, last_read_outbox_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
                )
                for (c in chats) {
                    chatStmt.bindLong(1, c.id)
                    chatStmt.bindString(2, c.title)
                    chatStmt.bindString(3, c.type)
                    chatStmt.bindLong(4, if (c.isArchived) 1L else 0L)
                    chatStmt.bindLong(5, c.unreadCount.toLong())
                    chatStmt.bindLong(6, c.lastReadInboxId)
                    chatStmt.bindLong(7, c.lastReadOutboxId)
                    chatStmt.executeInsert()
                }

                val msgStmt = db.compileStatement(
                    """
                    INSERT OR REPLACE INTO messages (
                        id, chat_id, sender_id, date, edit_date, is_outgoing,
                        reply_to_message_id, media_album_id, forward_info,
                        content_type, text, media_file_name, media_mime_type,
                        media_size, media_duration, media_width, media_height, extra_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """.trimIndent(),
                )
                for (m in messages) {
                    msgStmt.bindLong(1, m.id)
                    msgStmt.bindLong(2, m.chatId)
                    msgStmt.bindString(3, m.senderId)
                    msgStmt.bindLong(4, m.date.toLong())
                    msgStmt.bindLong(5, m.editDate.toLong())
                    msgStmt.bindLong(6, if (m.isOutgoing) 1L else 0L)
                    msgStmt.bindLong(7, m.replyToMessageId)
                    msgStmt.bindLong(8, m.mediaAlbumId)
                    msgStmt.bindString(9, m.forwardInfo)
                    msgStmt.bindString(10, m.contentType)
                    msgStmt.bindString(11, m.text)
                    msgStmt.bindString(12, m.mediaFileName)
                    msgStmt.bindString(13, m.mediaMimeType)
                    msgStmt.bindLong(14, m.mediaSize)
                    msgStmt.bindLong(15, m.mediaDuration.toLong())
                    msgStmt.bindLong(16, m.mediaWidth.toLong())
                    msgStmt.bindLong(17, m.mediaHeight.toLong())
                    msgStmt.bindString(18, m.extraJson)
                    msgStmt.executeInsert()
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            db.close()
        }
    }

    private fun extractMessageRow(chatId: Long, msg: TdApi.Message): MessageRow {
        val senderId = when (val s = msg.senderId) {
            is TdApi.MessageSenderUser -> "user:${s.userId}"
            is TdApi.MessageSenderChat -> "chat:${s.chatId}"
            else -> "unknown"
        }
        val replyToId = when (val r = msg.replyTo) {
            is TdApi.MessageReplyToMessage -> r.messageId
            else -> 0L
        }
        val forwardInfo = msg.forwardInfo?.let { fi ->
            val origin = when (val o = fi.origin) {
                is TdApi.MessageOriginUser -> "user:${o.senderUserId}"
                is TdApi.MessageOriginHiddenUser -> "hidden:${o.senderName}"
                is TdApi.MessageOriginChat -> "chat:${o.senderChatId}"
                is TdApi.MessageOriginChannel -> "channel:${o.chatId}:${o.messageId}"
                else -> o.javaClass.simpleName
            }
            "$origin@${fi.date}"
        } ?: ""

        val contentType = msg.content.javaClass.simpleName
        var text = ""
        var mediaFileName = ""
        var mediaMimeType = ""
        var mediaSize = 0L
        var mediaDuration = 0
        var mediaWidth = 0
        var mediaHeight = 0
        val extra = JSONObject()

        when (val c = msg.content) {
            is TdApi.MessageText -> {
                text = c.text?.text ?: ""
                c.linkPreview?.let { lp ->
                    extra.put("link_url", lp.url ?: "")
                    extra.put("link_title", lp.title ?: "")
                }
            }
            is TdApi.MessagePhoto -> {
                text = c.caption?.text ?: ""
                val best = c.photo.sizes.maxByOrNull { it.width * it.height }
                if (best != null) {
                    mediaWidth = best.width
                    mediaHeight = best.height
                    mediaSize = best.photo.size
                }
                mediaMimeType = "image/jpeg"
            }
            is TdApi.MessageVideo -> {
                text = c.caption?.text ?: ""
                mediaFileName = c.video.fileName ?: ""
                mediaMimeType = c.video.mimeType ?: ""
                mediaSize = c.video.video.size
                mediaDuration = c.video.duration
                mediaWidth = c.video.width
                mediaHeight = c.video.height
            }
            is TdApi.MessageDocument -> {
                text = c.caption?.text ?: ""
                mediaFileName = c.document.fileName ?: ""
                mediaMimeType = c.document.mimeType ?: ""
                mediaSize = c.document.document.size
            }
            is TdApi.MessageAudio -> {
                text = c.caption?.text ?: ""
                mediaFileName = c.audio.fileName ?: ""
                mediaMimeType = c.audio.mimeType ?: ""
                mediaSize = c.audio.audio.size
                mediaDuration = c.audio.duration
                extra.put("title", c.audio.title ?: "")
                extra.put("performer", c.audio.performer ?: "")
            }
            is TdApi.MessageVoiceNote -> {
                text = c.caption?.text ?: ""
                mediaMimeType = c.voiceNote.mimeType ?: ""
                mediaSize = c.voiceNote.voice.size
                mediaDuration = c.voiceNote.duration
            }
            is TdApi.MessageVideoNote -> {
                mediaSize = c.videoNote.video.size
                mediaDuration = c.videoNote.duration
                mediaWidth = c.videoNote.length
                mediaHeight = c.videoNote.length
            }
            is TdApi.MessageAnimation -> {
                text = c.caption?.text ?: ""
                mediaFileName = c.animation.fileName ?: ""
                mediaMimeType = c.animation.mimeType ?: ""
                mediaSize = c.animation.animation.size
                mediaDuration = c.animation.duration
                mediaWidth = c.animation.width
                mediaHeight = c.animation.height
            }
            is TdApi.MessageSticker -> {
                text = c.sticker.emoji ?: ""
                mediaWidth = c.sticker.width
                mediaHeight = c.sticker.height
                mediaSize = c.sticker.sticker.size
                extra.put("set_id", c.sticker.setId)
            }
            is TdApi.MessageLocation -> {
                extra.put("latitude", c.location.latitude)
                extra.put("longitude", c.location.longitude)
            }
            is TdApi.MessageContact -> {
                extra.put("phone_number", c.contact.phoneNumber ?: "")
                extra.put("first_name", c.contact.firstName ?: "")
                extra.put("last_name", c.contact.lastName ?: "")
                extra.put("user_id", c.contact.userId)
            }
            is TdApi.MessagePoll -> {
                text = c.poll.question?.text ?: ""
                extra.put("total_voter_count", c.poll.totalVoterCount)
                extra.put("is_closed", c.poll.isClosed)
            }
            is TdApi.MessageCall -> {
                mediaDuration = c.duration
                extra.put("is_video", c.isVideo)
                extra.put("discard_reason", c.discardReason?.javaClass?.simpleName ?: "")
            }
            else -> {
                extra.put("raw_type", contentType)
            }
        }

        return MessageRow(
            id = msg.id,
            chatId = chatId,
            senderId = senderId,
            date = msg.date,
            editDate = msg.editDate,
            isOutgoing = msg.isOutgoing,
            replyToMessageId = replyToId,
            mediaAlbumId = msg.mediaAlbumId,
            forwardInfo = forwardInfo,
            contentType = contentType,
            text = text,
            mediaFileName = mediaFileName,
            mediaMimeType = mediaMimeType,
            mediaSize = mediaSize,
            mediaDuration = mediaDuration,
            mediaWidth = mediaWidth,
            mediaHeight = mediaHeight,
            extraJson = if (extra.length() > 0) extra.toString() else "",
        )
    }

    private data class UserRow(
        val id: Long,
        val firstName: String,
        val lastName: String,
        val username: String,
        val phoneNumber: String,
        val isContact: Boolean,
        val type: String,
    )

    private data class ChatRow(
        val id: Long,
        val title: String,
        val type: String,
        val isArchived: Boolean,
        val unreadCount: Int,
        val lastReadInboxId: Long,
        val lastReadOutboxId: Long,
    )

    private data class MessageRow(
        val id: Long,
        val chatId: Long,
        val senderId: String,
        val date: Int,
        val editDate: Int,
        val isOutgoing: Boolean,
        val replyToMessageId: Long,
        val mediaAlbumId: Long,
        val forwardInfo: String,
        val contentType: String,
        val text: String,
        val mediaFileName: String,
        val mediaMimeType: String,
        val mediaSize: Long,
        val mediaDuration: Int,
        val mediaWidth: Int,
        val mediaHeight: Int,
        val extraJson: String,
    )
}
