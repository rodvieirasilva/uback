package uback.rodvieirasilva.github.io

import android.content.Context
import android.util.Log
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors

/**
 * Modular transfer runners extracted from [BackupForegroundService] to keep each file focused
 * and avoid duplicating post-verification watermark/cleanup logic.
 */
object BackupRunners {
    private const val TAG = "UBack"
    private const val SMALL_FILE_THRESHOLD_BYTES = 5L * 1024L * 1024L

    data class RunnerCallbacks(
        val onItemVerified: (item: BackupItemPayload, skipped: Boolean) -> Unit,
        val onItemError: (item: BackupItemPayload, message: String) -> Unit,
        val onItemProgress: (fileName: String, stage: String, inFlightBytes: Long) -> Unit,
        val onResetFileTimer: (Long) -> Unit,
        val onFatalError: (fileName: String, message: String) -> Unit,
        val onCancelled: (fileName: String) -> Unit,
        val onCompleted: () -> Unit,
        val onTouchActivity: () -> Unit,
    )

    fun finalizeVerifiedItem(context: Context, mode: String, item: BackupItemPayload) {
        if (!item.deltaScope.isNullOrBlank() && item.deltaMaxRowId > 0L) {
            WhatsAppDeltaState.commitWatermark(context, item.deltaScope, item.deltaMaxRowId)
        }
        if (item.id.startsWith("telegram_delta_")) {
            TelegramDeltaExporter.commitWatermark(context, item.id)
        }
        if (item.isSnapshot) {
            runCatching { File(item.localPath).delete() }
        } else if (mode == "crop" && !item.isReadOnly) {
            MediaCleaner.deleteVerifiedFile(context, item.localPath, item.contentUri)
        }
    }

    fun runS3Backup(
        context: Context,
        request: BackupJobRequest,
        s3Cfg: S3BackupClient.S3Config,
        cb: RunnerCallbacks,
    ) {
        val (ok, msg) = S3BackupClient.testConnection(s3Cfg)
        if (!ok) {
            cb.onFatalError("S3 Connection", msg)
            return
        }
        val zone = ZoneId.systemDefault()
        for (item in request.items) {
            if (BackupSessionBus.cancelRequested.get()) {
                cb.onCancelled(item.fileName)
                return
            }
            val localDate = Instant.ofEpochMilli(item.createdAtMs).atZone(zone).toLocalDate()
            val relPath = listOf(
                request.deviceFolder,
                item.sourceFolder,
                "%04d".format(localDate.year),
                "%02d".format(localDate.monthValue),
                item.fileName,
            ).filter { it.isNotBlank() }.joinToString("/")
            try {
                cb.onResetFileTimer(item.sizeBytes)
                cb.onItemProgress(item.fileName, "uploading", 0L)
                val outcome = S3BackupClient.uploadAndVerify(
                    cfg = s3Cfg,
                    localFile = File(item.localPath),
                    relativePath = relPath,
                    onProgress = { copied -> cb.onItemProgress(item.fileName, "uploading", copied) },
                    isCancelled = { BackupSessionBus.cancelRequested.get() },
                )
                finalizeVerifiedItem(context, request.mode, item)
                cb.onItemVerified(item, outcome.skipped)
            } catch (_: InterruptedException) {
                cb.onCancelled(item.fileName)
                return
            } catch (e: Throwable) {
                cb.onItemError(item, e.message ?: e.javaClass.simpleName)
            }
        }
        cb.onCompleted()
    }

    /**
     * Runs small non-snapshot files (<= 5 MB) concurrently across bounded SMB workers and returns
     * the remaining items to be processed sequentially on the primary connection.
     */
    fun runParallelSmbSmallFiles(
        context: Context,
        request: BackupJobRequest,
        zone: ZoneId,
        cb: RunnerCallbacks,
    ): List<BackupItemPayload> {
        if (!request.smbParallelEnabled) return request.items
        val (smallItems, largeItems) = request.items.partition {
            !it.isSnapshot && it.sizeBytes <= SMALL_FILE_THRESHOLD_BYTES
        }
        if (smallItems.size < 2) return request.items

        val workerCount = request.smbParallelWorkers.coerceIn(2, 4)
        Log.i(TAG, "SMB parallel small-file workers active: ${smallItems.size} small files across $workerCount workers")
        val queue = ConcurrentLinkedQueue(smallItems)
        val counterLock = Any()
        val pool = Executors.newFixedThreadPool(workerCount)
        try {
            val tasks = (1..workerCount).map {
                pool.submit {
                    val workerClient = SmbTransferClient(request.smbConfig)
                    try {
                        workerClient.reconnect()
                        while (!BackupSessionBus.cancelRequested.get()) {
                            val item = queue.poll() ?: break
                            val localDate = Instant.ofEpochMilli(item.createdAtMs).atZone(zone).toLocalDate()
                            val remoteDirRel = listOf(
                                request.smbConfig.basePath,
                                request.deviceFolder,
                                item.sourceFolder,
                                "%04d".format(localDate.year),
                                "%02d".format(localDate.monthValue),
                            ).filter { it.isNotBlank() }.joinToString("/")
                            try {
                                val result = workerClient.backupFileWithVerification(
                                    localFile = File(item.localPath),
                                    remoteDirRel = remoteDirRel,
                                    fileName = item.fileName,
                                    createdAtMs = item.createdAtMs,
                                    onStage = {},
                                    onBytesProgress = {},
                                    isCancelled = { BackupSessionBus.cancelRequested.get() },
                                )
                                finalizeVerifiedItem(context, request.mode, item)
                                synchronized(counterLock) {
                                    cb.onTouchActivity()
                                    cb.onItemVerified(item, result.outcome == TransferOutcome.SKIPPED_ALREADY_VERIFIED)
                                }
                            } catch (_: InterruptedException) {
                                break
                            } catch (e: Throwable) {
                                synchronized(counterLock) {
                                    cb.onItemError(item, e.message ?: e.javaClass.simpleName)
                                }
                            }
                        }
                    } finally {
                        workerClient.close()
                    }
                }
            }
            tasks.forEach { it.get() }
        } finally {
            pool.shutdownNow()
        }
        return largeItems
    }
}
