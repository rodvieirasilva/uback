package uback.rodvieirasilva.github.io

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicBoolean

data class BackupItemPayload(
    val id: String,
    val contentUri: String?,
    val fileName: String,
    val localPath: String,
    val sourceFolder: String,
    val sizeBytes: Long,
    val createdAtMs: Long,
    val isSnapshot: Boolean = false,
)

data class BackupJobRequest(
    val smbConfig: SmbConnectionConfig,
    val mode: String, // "copy" or "crop"
    val deviceFolder: String,
    val items: List<BackupItemPayload>,
)

object BackupSessionBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var listener: ((Map<String, Any?>) -> Unit)? = null

    @Volatile
    var latestEvent: Map<String, Any?> = idleState()
        private set

    @Volatile
    var pendingRequest: BackupJobRequest? = null

    val isRunning = AtomicBoolean(false)
    val cancelRequested = AtomicBoolean(false)
    val pauseRequested = AtomicBoolean(false)
    private val pauseLock = Object()

    fun requestPause() {
        if (!isRunning.get() || cancelRequested.get()) return
        pauseRequested.set(true)
        val snap = latestEvent.toMutableMap()
        if (snap["state"] == "running") {
            snap["state"] = "paused"
            snap["stage"] = "paused"
            emit(snap)
        }
        synchronized(pauseLock) { pauseLock.notifyAll() }
    }

    fun requestResume() {
        pauseRequested.set(false)
        val snap = latestEvent.toMutableMap()
        if (snap["state"] == "paused") {
            snap["state"] = "running"
            snap["stage"] = "resuming"
            emit(snap)
        }
        synchronized(pauseLock) { pauseLock.notifyAll() }
    }

    fun requestCancel() {
        cancelRequested.set(true)
        pauseRequested.set(false)
        synchronized(pauseLock) { pauseLock.notifyAll() }
    }

    fun waitIfPaused(onEnterPaused: () -> Unit, onResumed: () -> Unit) {
        if (!pauseRequested.get()) return
        onEnterPaused()
        synchronized(pauseLock) {
            while (pauseRequested.get() && !cancelRequested.get()) {
                runCatching { pauseLock.wait(250L) }
            }
        }
        if (cancelRequested.get()) {
            throw InterruptedException("Backup cancelled while paused")
        }
        onResumed()
    }

    fun idleState(): Map<String, Any?> = mapOf(
        "state" to "idle",
        "stage" to "idle",
        "total" to 0,
        "transferred" to 0,
        "skipped" to 0,
        "failed" to 0,
        "remaining" to 0,
        "bytesTransferred" to 0L,
        "totalBytes" to 0L,
        "elapsedMs" to 0L,
        "etaMs" to -1L,
        "currentFile" to "",
        "errors" to emptyList<Map<String, String>>(),
    )

    fun setListener(cb: ((Map<String, Any?>) -> Unit)?) {
        listener = cb
        if (cb != null) {
            val snap = latestEvent
            mainHandler.post { cb(snap) }
        }
    }

    fun emit(event: Map<String, Any?>) {
        latestEvent = event
        val cb = listener ?: return
        mainHandler.post { cb(event) }
    }
}

class BackupForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var activeJob: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                BackupSessionBus.requestCancel()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                BackupSessionBus.requestPause()
                return START_NOT_STICKY
            }
            ACTION_RESUME -> {
                BackupSessionBus.requestResume()
                return START_NOT_STICKY
            }
        }

        val request = BackupSessionBus.pendingRequest
        if (request == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        BackupSessionBus.pendingRequest = null

        ensureNotificationChannel()
        val modeVerb = if (request.mode == "crop") "Moving" else "Backing up"
        val initialNotification = buildProgressNotification(
            title = "UBack • $modeVerb media (0%)",
            summary = "Preparing ${request.items.size} files...",
            detail = "Connecting to SMB server",
            permille = 0,
            indeterminate = true,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                initialNotification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, initialNotification)
        }

        acquireLocks()
        activeJob?.cancel()
        activeJob = serviceScope.launch {
            try {
                runBackup(request)
            } finally {
                releaseLocks()
                BackupSessionBus.isRunning.set(false)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun runBackup(request: BackupJobRequest) {
        BackupSessionBus.isRunning.set(true)
        BackupSessionBus.cancelRequested.set(false)
        BackupSessionBus.pauseRequested.set(false)

        val total = request.items.size
        val totalBytes = request.items.sumOf { it.sizeBytes }
        var transferred = 0
        var skipped = 0
        var failed = 0
        var completedBytes = 0L
        val errors = mutableListOf<Map<String, String>>()
        var activeElapsedMs = 0L
        var activeSegmentStartMs = SystemClock.elapsedRealtime()

        fun currentElapsedMs(): Long {
            val runningDelta = if (activeSegmentStartMs > 0L) {
                (SystemClock.elapsedRealtime() - activeSegmentStartMs).coerceAtLeast(0L)
            } else {
                0L
            }
            return activeElapsedMs + runningDelta
        }

        fun pauseTimer() {
            if (activeSegmentStartMs > 0L) {
                activeElapsedMs += (SystemClock.elapsedRealtime() - activeSegmentStartMs).coerceAtLeast(0L)
                activeSegmentStartMs = 0L
            }
        }

        fun resumeTimer() {
            if (activeSegmentStartMs == 0L) {
                activeSegmentStartMs = SystemClock.elapsedRealtime()
            }
        }

        fun emitProgress(
            state: String,
            stage: String,
            currentFile: String,
            inFlightBytes: Long = 0L,
        ) {
            val done = transferred + skipped + failed
            val remaining = (total - done).coerceAtLeast(0)
            val bytesNow = (completedBytes + inFlightBytes).coerceAtMost(totalBytes)
            val elapsedMs = currentElapsedMs()
            val etaMs = when {
                state == "completed" -> 0L
                state == "running" && elapsedMs >= 800L && bytesNow > 0L && totalBytes > bytesNow -> {
                    val bytesPerMs = bytesNow.toDouble() / elapsedMs.toDouble()
                    if (bytesPerMs > 0.0) {
                        ((totalBytes - bytesNow) / bytesPerMs).toLong().coerceAtLeast(0L)
                    } else {
                        -1L
                    }
                }
                else -> -1L
            }
            BackupSessionBus.emit(
                mapOf(
                    "state" to state,
                    "stage" to stage,
                    "total" to total,
                    "transferred" to transferred,
                    "skipped" to skipped,
                    "failed" to failed,
                    "remaining" to remaining,
                    "bytesTransferred" to bytesNow,
                    "totalBytes" to totalBytes,
                    "elapsedMs" to elapsedMs,
                    "etaMs" to etaMs,
                    "currentFile" to currentFile,
                    "errors" to errors.toList(),
                ),
            )
            val modeVerb = if (request.mode == "crop") "Moving" else "Backing up"
            val pct = when {
                totalBytes > 0L -> ((bytesNow * 100L) / totalBytes).toInt().coerceIn(0, 100)
                total > 0 -> ((done * 100) / total).coerceIn(0, 100)
                else -> 0
            }
            val permille = when {
                totalBytes > 0L -> ((bytesNow * 1000L) / totalBytes).toInt().coerceIn(0, 1000)
                total > 0 -> ((done * 1000) / total).coerceIn(0, 1000)
                else -> 0
            }
            val stageLabel = when (stage) {
                "connecting" -> "Connecting to NAS"
                "hashing" -> "Hashing SHA-256"
                "uploading" -> "Uploading"
                "verifying" -> "Verifying SHA-256 read-back"
                "cleaning_up" -> "Freeing local space"
                "retrying" -> "Retrying SMB transfer"
                "paused" -> "Paused — tap Resume to continue"
                "resuming" -> "Resuming transfer"
                else -> stage.replaceFirstChar { it.uppercase() }
            }
            val timingSuffix = if (etaMs >= 0L && state == "running") {
                " • Elapsed ${formatDuration(elapsedMs)} • ETA ~${formatDuration(etaMs)}"
            } else if (elapsedMs > 0L) {
                " • Elapsed ${formatDuration(elapsedMs)}"
            } else {
                ""
            }
            val summary = "$done / $total • $remaining remaining (${formatBytes(bytesNow)} / ${formatBytes(totalBytes)})$timingSuffix"
            val detail = if (currentFile.isNotBlank()) "$stageLabel: $currentFile" else stageLabel

            if (state == "running" || state == "paused") {
                updateProgressNotification(
                    title = if (state == "paused") "UBack • Backup paused ($pct%)" else "UBack • $modeVerb media ($pct%)",
                    summary = summary,
                    detail = detail,
                    permille = permille,
                    indeterminate = total == 0,
                    isPaused = state == "paused",
                )
            } else if (state == "completed" || state == "cancelled" || state == "error") {
                postCompletionNotification(
                    state = state,
                    transferred = transferred,
                    skipped = skipped,
                    failed = failed,
                )
            }
        }

        emitProgress(state = "running", stage = "connecting", currentFile = "")

        val smbClient = SmbTransferClient(request.smbConfig)
        try {
            smbClient.reconnect()
            val zone = ZoneId.systemDefault()

            for (item in request.items) {
                val pauseGate = {
                    BackupSessionBus.waitIfPaused(
                        onEnterPaused = {
                            pauseTimer()
                            emitProgress(state = "paused", stage = "paused", currentFile = item.fileName)
                        },
                        onResumed = {
                            resumeTimer()
                            emitProgress(state = "running", stage = "resuming", currentFile = item.fileName)
                        },
                    )
                }
                try {
                    pauseGate()
                } catch (_: InterruptedException) {
                    emitProgress(state = "cancelled", stage = "cancelled", currentFile = item.fileName)
                    return
                }
                if (BackupSessionBus.cancelRequested.get()) {
                    emitProgress(state = "cancelled", stage = "cancelled", currentFile = item.fileName)
                    return
                }

                val localDate = Instant.ofEpochMilli(item.createdAtMs).atZone(zone).toLocalDate()
                val yyyy = "%04d".format(localDate.year)
                val mm = "%02d".format(localDate.monthValue)
                val remoteDirRel = listOf(
                    request.smbConfig.basePath,
                    request.deviceFolder,
                    item.sourceFolder,
                    yyyy,
                    mm,
                ).filter { it.isNotBlank() }.joinToString("/")

                try {
                    val result = smbClient.backupFileWithVerification(
                        localFile = File(item.localPath),
                        remoteDirRel = remoteDirRel,
                        fileName = item.fileName,
                        createdAtMs = item.createdAtMs,
                        onStage = { stage ->
                            emitProgress(
                                state = "running",
                                stage = stage,
                                currentFile = item.fileName,
                            )
                        },
                        onBytesProgress = { uploadedBytes ->
                            emitProgress(
                                state = "running",
                                stage = "uploading",
                                currentFile = item.fileName,
                                inFlightBytes = uploadedBytes,
                            )
                        },
                        isCancelled = { BackupSessionBus.cancelRequested.get() },
                        waitIfPaused = pauseGate,
                    )

                    // Snapshot temp files live in app cache — always remove temp file after verified upload,
                    // never touching actual Android Contacts / SMS / Call Logs even in Crop Mode.
                    if (item.isSnapshot) {
                        runCatching { File(item.localPath).delete() }
                    } else if (request.mode == "crop") {
                        // Strict Deletion Gate (Crop Mode): delete ONLY after full SHA-256 verification succeeded!
                        emitProgress(
                            state = "running",
                            stage = "cleaning_up",
                            currentFile = item.fileName,
                            inFlightBytes = item.sizeBytes,
                        )
                        val deleted = MediaCleaner.deleteVerifiedFile(
                            context = applicationContext,
                            localPath = item.localPath,
                            contentUriStr = item.contentUri,
                        )
                        if (!deleted) {
                            errors.add(
                                mapOf(
                                    "fileName" to item.fileName,
                                    "message" to "Verified on NAS, but failed to delete local file (grant All Files Access).",
                                ),
                            )
                            failed++
                            completedBytes += item.sizeBytes
                            emitProgress(state = "running", stage = "verifying", currentFile = item.fileName)
                            continue
                        }
                    }

                    when (result.outcome) {
                        TransferOutcome.TRANSFERRED_VERIFIED -> transferred++
                        TransferOutcome.SKIPPED_ALREADY_VERIFIED -> skipped++
                    }
                    completedBytes += item.sizeBytes
                    emitProgress(state = "running", stage = "verified", currentFile = item.fileName)
                } catch (_: InterruptedException) {
                    emitProgress(state = "cancelled", stage = "cancelled", currentFile = item.fileName)
                    return
                } catch (e: Throwable) {
                    android.util.Log.e("UBack", "Backup failed for ${item.fileName}", e)
                    failed++
                    errors.add(
                        mapOf(
                            "fileName" to item.fileName,
                            "message" to (e.message ?: e.javaClass.simpleName),
                        ),
                    )
                    emitProgress(state = "running", stage = "error", currentFile = item.fileName)
                }
            }

            emitProgress(state = "completed", stage = "completed", currentFile = "")
        } catch (e: Throwable) {
            errors.add(
                mapOf(
                    "fileName" to "SMB Connection",
                    "message" to (e.message ?: e.javaClass.simpleName),
                ),
            )
            emitProgress(state = "error", stage = "error", currentFile = "")
        } finally {
            runCatching { smbClient.close() }
        }
    }

    private fun ensureNotificationChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "UBack Backup Progress",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows verified SMB backup progress"
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun pauseResumePendingIntent(isPaused: Boolean): PendingIntent {
        val intent = Intent(this, BackupForegroundService::class.java).apply {
            action = if (isPaused) ACTION_RESUME else ACTION_PAUSE
        }
        return PendingIntent.getService(
            this,
            if (isPaused) 3 else 2,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopActionPendingIntent(): PendingIntent {
        val intent = Intent(this, BackupForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        return PendingIntent.getService(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildProgressNotification(
        title: String,
        summary: String,
        detail: String,
        permille: Int,
        indeterminate: Boolean,
        isPaused: Boolean = false,
    ): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText("$summary\n$detail"))
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(openAppPendingIntent())
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setProgress(1000, permille, indeterminate)
            .addAction(
                if (isPaused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (isPaused) "Resume" else "Pause",
                pauseResumePendingIntent(isPaused),
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopActionPendingIntent(),
            )
            .build()
    }

    private fun updateProgressNotification(
        title: String,
        summary: String,
        detail: String,
        permille: Int,
        indeterminate: Boolean,
        isPaused: Boolean = false,
    ) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            NOTIFICATION_ID,
            buildProgressNotification(title, summary, detail, permille, indeterminate, isPaused),
        )
    }

    private fun postCompletionNotification(
        state: String,
        transferred: Int,
        skipped: Int,
        failed: Int,
    ) {
        val title = when (state) {
            "completed" -> if (failed == 0) "UBack • Backup complete" else "UBack • Completed with errors"
            "cancelled" -> "UBack • Backup stopped"
            else -> "UBack • Backup error"
        }
        val body = "Transferred: $transferred • Skipped: $skipped • Failed: $failed"
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(openAppPendingIntent())
            .setAutoCancel(true)
            .setOngoing(false)
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(COMPLETION_NOTIFICATION_ID, notification)
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes <= 0L) return "0 B"
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var v = bytes.toDouble()
        var idx = 0
        while (v >= 1024.0 && idx < units.lastIndex) {
            v /= 1024.0
            idx++
        }
        return if (idx == 0) "$bytes B" else "%.1f %s".format(v, units[idx])
    }

    private fun formatDuration(ms: Long): String {
        val totalSec = (ms / 1000L).coerceAtLeast(0L)
        val hours = totalSec / 3600L
        val mins = (totalSec % 3600L) / 60L
        val secs = totalSec % 60L
        return if (hours > 0L) {
            "%d:%02d:%02d".format(hours, mins, secs)
        } else {
            "%02d:%02d".format(mins, secs)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        runCatching {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "uback:backup_wake_lock")
                .apply { acquire(4 * 60 * 60 * 1000L) }
        }
        runCatching {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wm.createWifiLock(mode, "uback:backup_wifi_lock").apply { acquire() }
        }
    }

    private fun releaseLocks() {
        runCatching {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        }
        runCatching {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        }
        wakeLock = null
        wifiLock = null
    }

    override fun onDestroy() {
        BackupSessionBus.requestCancel()
        serviceScope.cancel()
        releaseLocks()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "uback.rodvieirasilva.github.io.ACTION_START"
        const val ACTION_PAUSE = "uback.rodvieirasilva.github.io.ACTION_PAUSE"
        const val ACTION_RESUME = "uback.rodvieirasilva.github.io.ACTION_RESUME"
        const val ACTION_STOP = "uback.rodvieirasilva.github.io.ACTION_STOP"
        private const val CHANNEL_ID = "uback_backup_channel"
        private const val NOTIFICATION_ID = 4201
        private const val COMPLETION_NOTIFICATION_ID = 4202
    }
}
