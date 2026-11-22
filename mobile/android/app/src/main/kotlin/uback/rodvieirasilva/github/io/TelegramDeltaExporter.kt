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
    private const val CURRENT_SCHEMA_VERSION = 3
    private const val KEY_WATERMARKS_PREFIX = "chat_wm_"
    private const val KEY_BACKFILL_PREFIX = "chat_bf_"
    private const val MAX_CHATS_QUERY = 2_000
    private const val PAGE_SIZE = 100
    private const val MAX_MSGS_PER_CHAT_PER_RUN = 1_000
    private const val MAX_RUN_DURATION_MS = 45_000L
    private const val REMOTE_SUBPATH = "telegram/deltas"

    private val exportLock = Any()
    private val pendingCursors = ConcurrentHashMap<String, Map<Long, Pair<Long, Long>>>()

    private fun ensureSchemaVersion(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val version = prefs.getInt(KEY_SCHEMA_VERSION, 0)
        if (version < CURRENT_SCHEMA_VERSION) {
            // Reset legacy partial v1 watermarks once so full-history v2 backfill runs cleanly.
            prefs.edit().clear().putInt(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION).apply()
            Log.i(TAG, "Telegram delta: upgraded state schema $version -> $CURRENT_SCHEMA_VERSION (full backfill enabled)")
        }
    }

    private fun loadAllChatIds(fetchMoreFromServer: Boolean): List<Pair<Long, Boolean>> {
        val seen = LinkedHashSet<Long>()
        val result = mutableListOf<Pair<Long, Boolean>>()
        val lists = listOf(
            TdApi.ChatListMain() to false,
            TdApi.ChatListArchive() to true,
        )
        for ((chatList, isArchived) in lists) {
            if (fetchMoreFromServer) {
                for (attempt in 0 until 5) {
                    val res = TelegramClientManager.query(TdApi.LoadChats(chatList, 200), timeoutSeconds = 5)
                    if (res is TdApi.Error || res == null) break
                }
            }
            val chatsObj = TelegramClientManager.query(TdApi.GetChats(chatList, MAX_CHATS_QUERY), timeoutSeconds = 5)
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
        val chatPairs = loadAllChatIds(fetchMoreFromServer = false)
        var chatsWithNew = 0
        for ((chatId, _) in chatPairs) {
            val chatObj = TelegramClientManager.query(TdApi.GetChat(chatId), timeoutSeconds = 3) as? TdApi.Chat ?: continue
            val lastMsgId = chatObj.lastMessage?.id ?: 0L
            val wm = prefs.getLong("$KEY_WATERMARKS_PREFIX$chatId", 0L)
            val bf = prefs.getLong("$KEY_BACKFILL_PREFIX$chatId", 0L)
            if (lastMsgId > wm || bf > 0L) {
                chatsWithNew++
            }
        }
        return if (chatsWithNew > 0) {
            mapOf("telegram.deltas" to mapOf("count" to 1, "totalBytes" to chatsWithNew * 16384L))
        } else {
            mapOf("telegram.deltas" to mapOf("count" to 0, "totalBytes" to 0L))
        }
    }

    fun exportEnabledDeltas(
        context: Context,
        enabledSources: Set<String>,
    ): List<DiscoveredMediaItem> = synchronized(exportLock) {
        if ("telegram.deltas" !in enabledSources) return emptyList()
        ensureSchemaVersion(context)
        TelegramClientManager.ensureInitializedFromPrefs(context)
        val state = TelegramClientManager.getAuthState()["state"] as? String
        if (state != "ready") {
            Log.i(TAG, "Telegram delta: not authenticated (state=$state, skipped)")
            return emptyList()
        }

        val chatPairs = loadAllChatIds(fetchMoreFromServer = true)
        if (chatPairs.isEmpty()) {
            Log.i(TAG, "Telegram delta: 0 chats returned (skipped)")
            return emptyList()
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val loadedChats = mutableListOf<Pair<TdApi.Chat, Boolean>>()
        for ((chatId, isArchived) in chatPairs) {
            val chat = TelegramClientManager.query(TdApi.GetChat(chatId), timeoutSeconds = 3) as? TdApi.Chat ?: continue
            val lastMsgId = chat.lastMessage?.id ?: 0L
            val wm = prefs.getLong("$KEY_WATERMARKS_PREFIX$chatId", 0L)
            val bf = prefs.getLong("$KEY_BACKFILL_PREFIX$chatId", 0L)
            if (lastMsgId > wm || bf > 0L) {
                loadedChats.add(chat to isArchived)
            }
        }
        // Prioritize private 1-on-1 chats and normal groups ahead of giant broadcast channels.
        loadedChats.sortBy { (chat, _) ->
            when (val t = chat.type) {
                is TdApi.ChatTypePrivate -> 0
                is TdApi.ChatTypeBasicGroup -> 1
                is TdApi.ChatTypeSupergroup -> if (t.isChannel) 3 else 2
                else -> 4
            }
        }

        val cursorUpdates = mutableMapOf<Long, Pair<Long, Long>>()
        val exportedChats = mutableListOf<ChatRow>()
        val exportedMessages = mutableListOf<MessageRow>()
        val referencedUserIds = LinkedHashSet<Long>()
        val runStartMs = System.currentTimeMillis()
        var consecutiveTimeouts = 0

        for ((idx, pair) in loadedChats.withIndex()) {
            if (exportedMessages.isNotEmpty() && System.currentTimeMillis() - runStartMs >= MAX_RUN_DURATION_MS) {
                Log.i(TAG, "Telegram delta: reached 45s batch budget at chat $idx/${loadedChats.size}; remaining chats will continue next run")
                break
            }
            val (chat, isArchived) = pair
            val chatId = chat.id
            val wm = prefs.getLong("$KEY_WATERMARKS_PREFIX$chatId", 0L)
            val existingBf = prefs.getLong("$KEY_BACKFILL_PREFIX$chatId", 0L)

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

            var newWm = wm
            var newBf = existingBf
            var chatMsgCount = 0

            // Pass A: Fetch new messages newer than watermark (or start initial backfill if wm == 0)
            if ((chat.lastMessage?.id ?: 0L) > wm) {
                var fromMsgId = 0L
                var oldestInPass = Long.MAX_VALUE
                var reachedEnd = false
                while (chatMsgCount < MAX_MSGS_PER_CHAT_PER_RUN) {
                    if (exportedMessages.isNotEmpty() && System.currentTimeMillis() - runStartMs >= MAX_RUN_DURATION_MS) {
                        break
                    }
                    val historyObj = TelegramClientManager.query(
                        TdApi.GetChatHistory(chatId, fromMsgId, 0, PAGE_SIZE, false),
                        timeoutSeconds = 6,
                    )
                    if (historyObj == null || historyObj is TdApi.Error) {
                        consecutiveTimeouts++
                        break
                    }
                    consecutiveTimeouts = 0
                    val msgs = (historyObj as? TdApi.Messages)?.messages ?: break
                    if (msgs.isEmpty()) {
                        reachedEnd = true
                        break
                    }
                    var hitWm = false
                    for (msg in msgs) {
                        if (msg.id <= wm) {
                            hitWm = true
                            break
                        }
                        if (msg.id > newWm) newWm = msg.id
                        if (msg.id < oldestInPass) oldestInPass = msg.id
                        val sender = msg.senderId
                        if (sender is TdApi.MessageSenderUser) referencedUserIds.add(sender.userId)
                        exportedMessages.add(extractMessageRow(chatId, msg))
                        chatMsgCount++
                    }
                    val oldestInPage = msgs.last().id
                    if (hitWm || oldestInPage == fromMsgId) {
                        reachedEnd = true
                        break
                    }
                    fromMsgId = oldestInPage
                    Thread.sleep(30)
                }
                if (wm == 0L) {
                    newBf = if (reachedEnd || oldestInPass == Long.MAX_VALUE) 0L else oldestInPass
                }
            }

            // Pass B: Resume older-history backfill if chat still has an active backfill cursor
            if (existingBf > 0L && chatMsgCount < MAX_MSGS_PER_CHAT_PER_RUN) {
                var fromMsgId = existingBf
                var reachedBeginning = false
                while (chatMsgCount < MAX_MSGS_PER_CHAT_PER_RUN) {
                    if (exportedMessages.isNotEmpty() && System.currentTimeMillis() - runStartMs >= MAX_RUN_DURATION_MS) {
                        break
                    }
                    val historyObj = TelegramClientManager.query(
                        TdApi.GetChatHistory(chatId, fromMsgId, 0, PAGE_SIZE, false),
                        timeoutSeconds = 6,
                    )
                    if (historyObj == null || historyObj is TdApi.Error) {
                        consecutiveTimeouts++
                        break
                    }
                    consecutiveTimeouts = 0
                    val msgs = (historyObj as? TdApi.Messages)?.messages ?: break
                    if (msgs.isEmpty()) {
                        reachedBeginning = true
                        break
                    }
                    for (msg in msgs) {
                        if (msg.id >= fromMsgId) continue
                        val sender = msg.senderId
                        if (sender is TdApi.MessageSenderUser) referencedUserIds.add(sender.userId)
                        exportedMessages.add(extractMessageRow(chatId, msg))
                        chatMsgCount++
                    }
                    val oldestInPage = msgs.last().id
                    if (oldestInPage >= fromMsgId) {
                        reachedBeginning = true
                        break
                    }
                    fromMsgId = oldestInPage
                    Thread.sleep(30)
                }
                newBf = if (reachedBeginning) 0L else fromMsgId
            }

            if (newWm != wm || newBf != existingBf) {
                cursorUpdates[chatId] = newWm to newBf
            }
            Log.i(TAG, "Telegram delta: chat ${idx + 1}/${loadedChats.size} '${chat.title}' -> $chatMsgCount msgs (wm=$newWm, bf=$newBf)")
            if (consecutiveTimeouts >= 3) {
                Log.w(TAG, "Telegram delta: pausing batch after 3 consecutive TDLib timeouts")
                break
            }
        }

        if (exportedMessages.isEmpty()) {
            Log.i(TAG, "Telegram delta: 0 new messages across ${loadedChats.size} pending chats (skipped)")
            return emptyList()
        }

        val exportedUsers = mutableListOf<UserRow>()
        var userTimeouts = 0
        for (uid in referencedUserIds) {
            if (userTimeouts >= 3) break
            val user = TelegramClientManager.query(TdApi.GetUser(uid), timeoutSeconds = 3) as? TdApi.User
            if (user == null) {
                userTimeouts++
                continue
            }
            userTimeouts = 0
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
        pendingCursors[itemId] = cursorUpdates
        Log.i(
            TAG,
            "Telegram delta: exported ${exportedMessages.size} messages, ${exportedChats.size} chats, " +
                "${exportedUsers.size} users -> ${outFile.name} (${outFile.length()} bytes)",
        )

        listOf(
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
        val updates = pendingCursors.remove(itemId) ?: return
        val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
        editor.putInt(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION)
        for ((chatId, pair) in updates) {
            val (wm, bf) = pair
            editor.putLong("$KEY_WATERMARKS_PREFIX$chatId", wm)
            editor.putLong("$KEY_BACKFILL_PREFIX$chatId", bf)
        }
        editor.apply()
        Log.i(TAG, "Telegram delta: committed cursors for ${updates.size} chats ($itemId)")
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
