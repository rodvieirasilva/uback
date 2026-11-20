package uback.rodvieirasilva.github.io

import com.hierynomus.mserref.NtStatus
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msdtyp.FileTime
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.msfscc.fileinformation.FileBasicInformation
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2CreateOptions
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.security.bc.BCSecurityProvider
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import android.os.SystemClock
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.EnumSet
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

data class SmbConnectionConfig(
    val host: String,
    val port: Int,
    val share: String,
    val basePath: String,
    val username: String,
    val password: String,
    val domain: String,
) {
    companion object {
        fun fromMap(map: Map<*, *>): SmbConnectionConfig = SmbConnectionConfig(
            host = (map["host"] as? String ?: "").trim(),
            port = (map["port"] as? Number)?.toInt() ?: 445,
            share = (map["share"] as? String ?: "").trim().trim('/', '\\'),
            basePath = (map["basePath"] as? String ?: "").trim().trim('/', '\\'),
            username = (map["username"] as? String ?: "").trim(),
            password = map["password"] as? String ?: "",
            domain = (map["domain"] as? String ?: "").trim(),
        )
    }
}

enum class TransferOutcome {
    TRANSFERRED_VERIFIED,
    SKIPPED_ALREADY_VERIFIED,
}

data class TransferResult(
    val outcome: TransferOutcome,
    val remotePath: String,
    val sha256: String,
    val sizeBytes: Long,
)

class SmbTransferClient(private val config: SmbConnectionConfig) : AutoCloseable {

    private data class CachedRemoteFile(
        var sizeBytes: Long,
        var sha256: String? = null,
    )

    private val smbConfig: SmbConfig = SmbConfig.builder()
        .withSecurityProvider(BCSecurityProvider())
        .withBufferSize(HUGE_BUFFER_SIZE)
        .withTimeout(30, TimeUnit.SECONDS)
        .withReadTimeout(30, TimeUnit.SECONDS)
        .withWriteTimeout(30, TimeUnit.SECONDS)
        .withTransactTimeout(30, TimeUnit.SECONDS)
        .withSoTimeout(35, TimeUnit.SECONDS)
        .withMultiProtocolNegotiate(true)
        .build()

    private var client: SMBClient? = null
    private var connection: Connection? = null
    private var session: Session? = null
    private var diskShare: DiskShare? = null

    /**
     * Monotonic timestamp of the most recent local/remote I/O progress so the service
     * watchdog can abort and reconnect if an SMB socket ever wedges during screen lock.
     */
    val lastActivityAtMs = AtomicLong(SystemClock.elapsedRealtime())

    /**
     * Per-session cache of already-ensured remote directories and per-folder file entries
     * (`normDir` -> lowercase filename -> `(actualFileName, sizeBytes, cachedSha256)`).
     * Eliminates O(N^2) SMB `share.list()` and repeated folder existence round-trips.
     */
    private val ensuredDirs = HashSet<String>()
    private val dirCache = HashMap<String, MutableMap<String, Pair<String, CachedRemoteFile>>>()

    fun touchActivity() {
        lastActivityAtMs.set(SystemClock.elapsedRealtime())
    }

    fun forceAbortStalledSocket() {
        touchActivity()
        runCatching { connection?.close() }
        runCatching { client?.close() }
        diskShare = null
        session = null
        connection = null
        client = null
    }

    private fun ensureConnected(): DiskShare {
        touchActivity()
        val current = diskShare
        if (current != null && current.isConnected && connection?.isConnected == true) {
            return current
        }
        reconnect()
        return requireNotNull(diskShare) { "Failed to establish SMB share connection" }
    }

    fun reconnect() {
        touchActivity()
        closeConnectionOnly()
        require(config.host.isNotBlank()) { "SMB host is required" }
        require(config.share.isNotBlank()) { "SMB share name is required" }

        val c = SMBClient(smbConfig)
        client = c
        val conn = c.connect(config.host, config.port)
        connection = conn
        touchActivity()

        val auth = if (config.username.isBlank()) {
            AuthenticationContext.anonymous()
        } else {
            AuthenticationContext(
                config.username,
                config.password.toCharArray(),
                config.domain.ifBlank { null },
            )
        }
        val sess = conn.authenticate(auth)
        session = sess
        val share = sess.connectShare(config.share)
        if (share !is DiskShare) {
            share.close()
            throw IllegalStateException("SMB share '${config.share}' is not a disk share")
        }
        diskShare = share
        touchActivity()
    }

    fun testConnection(): String {
        val share = ensureConnected()
        if (config.basePath.isNotBlank()) {
            ensureDirectories(share, normalizeSmbPath(config.basePath))
        }
        return "Connected to smb://${config.host}:${config.port}/${config.share}" +
            if (config.basePath.isNotBlank()) "/${config.basePath}" else ""
    }

    /**
     * Streams [localFile] to [remoteDirRel]/[fileName] with:
     * 1. Local streaming SHA-256 calculation.
     * 2. Pre-flight idempotency check (remote size + SHA-256 read-back) & hash-suffix disambiguation.
     * 3. Atomic upload to `.uback.tmp`.
     * 4. Mandatory full SHA-256 read-back verification (always enabled).
     * 5. Atomic rename to final file + best-effort lastModified preservation + existence/size check.
     * 6. Up to [maxAttempts] retries with exponential backoff and full session reconnect.
     */
    fun backupFileWithVerification(
        localFile: File,
        remoteDirRel: String,
        fileName: String,
        createdAtMs: Long,
        onStage: (String) -> Unit,
        onBytesProgress: (Long) -> Unit,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit = { _, _, _ -> },
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit = {},
        maxAttempts: Int = 3,
    ): TransferResult {
        require(localFile.exists() && localFile.isFile) { "Local file not found: ${localFile.path}" }
        val localSize = localFile.length()
        require(localSize > 0L) { "Refusing to back up empty file: ${localFile.path}" }

        val dynamicBufSize = selectDynamicBufferSize(localSize)
        val normDir = normalizeSmbPath(remoteDirRel)
        var cachedLocalSha256: String? = null

        var lastError: Throwable? = null
        for (attempt in 1..maxAttempts) {
            waitIfPaused()
            if (isCancelled()) throw InterruptedException("Backup cancelled")
            try {
                val share = ensureConnected()
                ensureDirectories(share, normDir)

                // Check directory index to see if any existing file in normDir shares the same
                // filename or the exact same byte size (which requires pre-upload SHA-256).
                val dirIndex = getOrLoadDirIndex(share, normDir)
                val origKey = fileName.lowercase()
                val hasSameNameOrSizeCandidate = origKey in dirIndex ||
                    dirIndex.values.any { it.second.sizeBytes == localSize }

                val targetName: TargetResolution
                if (hasSameNameOrSizeCandidate) {
                    val preHash = cachedLocalSha256 ?: run {
                        waitIfPaused()
                        onStage("hashing")
                        onFileBytesProgress("hashing", 0L, localSize)
                        computeLocalSha256(
                            localFile = localFile,
                            totalSize = localSize,
                            bufferSize = dynamicBufSize,
                            onFileBytesProgress = onFileBytesProgress,
                            isCancelled = isCancelled,
                            waitIfPaused = waitIfPaused,
                        ).also { cachedLocalSha256 = it }
                    }
                    // Step 2: Pre-flight check & content-hash deduplication / collision resolution
                    targetName = resolveTargetFileName(
                        share = share,
                        normDir = normDir,
                        originalFileName = fileName,
                        localSize = localSize,
                        localSha256 = preHash,
                        bufferSize = dynamicBufSize,
                        onStage = onStage,
                        onFileBytesProgress = onFileBytesProgress,
                        isCancelled = isCancelled,
                        waitIfPaused = waitIfPaused,
                    )
                } else {
                    targetName = TargetResolution(fileName = fileName, alreadyVerified = false)
                }

                val targetPath = joinSmbPath(normDir, targetName.fileName)
                if (targetName.alreadyVerified) {
                    val verifiedSha = requireNotNull(cachedLocalSha256)
                    android.util.Log.i(
                        "UBack",
                        "Skipped $fileName — SHA-256 already matched remote ${targetName.fileName} (0 bytes copied)",
                    )
                    onBytesProgress(localSize)
                    onFileBytesProgress("verified", localSize, localSize)
                    return TransferResult(
                        outcome = TransferOutcome.SKIPPED_ALREADY_VERIFIED,
                        remotePath = targetPath.replace('\\', '/'),
                        sha256 = verifiedSha,
                        sizeBytes = localSize,
                    )
                }

                // Step 3: Atomic upload to `.uback.tmp` (with byte-offset resume if a partial `.uback.tmp` exists!)
                val tempPath = "$targetPath.uback.tmp"
                val existingTempSize = if (safeFileExists(share, tempPath)) {
                    runCatching { getRemoteFileSize(share, tempPath) }.getOrDefault(0L)
                } else {
                    0L
                }
                if (existingTempSize > localSize) {
                    runCatching { share.rm(tempPath) }
                }
                val resumeOffset = if (existingTempSize in 1L..localSize) existingTempSize else 0L

                waitIfPaused()
                val localSha256: String
                if (resumeOffset < localSize) {
                    onStage("uploading")
                    onFileBytesProgress("uploading", resumeOffset, localSize)
                    if (resumeOffset > 0L) {
                        onBytesProgress(resumeOffset)
                        android.util.Log.i(
                            "UBack",
                            "Resuming $fileName -> $tempPath from byte $resumeOffset / $localSize (buffer=${dynamicBufSize / 1024}KB)",
                        )
                    } else {
                        android.util.Log.i(
                            "UBack",
                            "Uploading $fileName -> $tempPath ($localSize bytes, single-pass=${cachedLocalSha256 == null}, buffer=${dynamicBufSize / 1024}KB)",
                        )
                    }
                    val streamedSha = uploadStream(
                        share = share,
                        localFile = localFile,
                        localSize = localSize,
                        remotePath = tempPath,
                        resumeOffset = resumeOffset,
                        bufferSize = dynamicBufSize,
                        computeHashOnTheFly = cachedLocalSha256 == null,
                        onBytesProgress = onBytesProgress,
                        onFileBytesProgress = onFileBytesProgress,
                        isCancelled = isCancelled,
                        waitIfPaused = waitIfPaused,
                    )
                    localSha256 = cachedLocalSha256 ?: streamedSha.also { cachedLocalSha256 = it }
                } else {
                    onBytesProgress(localSize)
                    android.util.Log.i(
                        "UBack",
                        "Found complete partial $tempPath ($localSize bytes); proceeding directly to SHA-256 verification",
                    )
                    localSha256 = cachedLocalSha256 ?: computeLocalSha256(
                        localFile = localFile,
                        totalSize = localSize,
                        bufferSize = dynamicBufSize,
                        onFileBytesProgress = onFileBytesProgress,
                        isCancelled = isCancelled,
                        waitIfPaused = waitIfPaused,
                    ).also { cachedLocalSha256 = it }
                }

                // Step 4: Mandatory full SHA-256 read-back verification (ALWAYS ON)
                waitIfPaused()
                onStage("verifying")
                onFileBytesProgress("verifying", 0L, localSize)
                android.util.Log.i("UBack", "Checking remote size for $tempPath")
                val remoteTempSize = getRemoteFileSize(share, tempPath)
                if (remoteTempSize != localSize) {
                    runCatching { share.rm(tempPath) }
                    throw IllegalStateException(
                        "Post-upload size mismatch for $fileName: expected $localSize, got $remoteTempSize",
                    )
                }

                android.util.Log.i(
                    "UBack",
                    "Reading back SHA-256 for $tempPath ($remoteTempSize bytes, buffer=${dynamicBufSize / 1024}KB)",
                )
                val remoteSha256 = computeRemoteSha256(
                    share = share,
                    remotePath = tempPath,
                    expectedSize = remoteTempSize,
                    bufferSize = dynamicBufSize,
                    onFileBytesProgress = onFileBytesProgress,
                    isCancelled = isCancelled,
                    waitIfPaused = waitIfPaused,
                )
                if (!remoteSha256.equals(localSha256, ignoreCase = true)) {
                    runCatching { share.rm(tempPath) }
                    throw IllegalStateException(
                        "Post-upload SHA-256 mismatch for $fileName: expected $localSha256, got $remoteSha256",
                    )
                }

                // Step 5: Atomic commit (rename .uback.tmp -> final target)
                android.util.Log.i("UBack", "Renaming $tempPath -> $targetPath")
                renameRemoteFile(share, tempPath, targetPath)

                // Best-effort timestamp preservation
                val targetTimeMs = if (createdAtMs > 0L) createdAtMs else localFile.lastModified()
                if (targetTimeMs > 0L) {
                    runCatching { setRemoteLastModified(share, targetPath, targetTimeMs) }
                }

                // Final sanity check after rename
                if (!safeFileExists(share, targetPath)) {
                    throw IllegalStateException("Final file missing after rename: $targetPath")
                }
                val finalSize = getRemoteFileSize(share, targetPath)
                if (finalSize != localSize) {
                    throw IllegalStateException(
                        "Final file size mismatch after rename: expected $localSize, got $finalSize",
                    )
                }

                recordVerifiedRemoteFile(normDir, targetName.fileName, localSize, localSha256)
                android.util.Log.i("UBack", "Verified & committed $targetPath (sha256=${localSha256.take(12)}...)")
                return TransferResult(
                    outcome = TransferOutcome.TRANSFERRED_VERIFIED,
                    remotePath = targetPath.replace('\\', '/'),
                    sha256 = localSha256,
                    sizeBytes = localSize,
                )
            } catch (e: InterruptedException) {
                throw e
            } catch (e: Throwable) {
                android.util.Log.w("UBack", "Attempt $attempt/$maxAttempts failed for $fileName", e)
                lastError = e
                // Invalidate cached directory listing for normDir on error so retry re-queries fresh state
                dirCache.remove(normDir)
                if (attempt < maxAttempts && !isCancelled()) {
                    waitIfPaused()
                    onStage("retrying")
                    runCatching { closeConnectionOnly() }
                    val backoffMs = 1000L * (1L shl (attempt - 1))
                    Thread.sleep(backoffMs)
                }
            }
        }
        throw lastError ?: IllegalStateException("Transfer failed for $fileName")
    }

    private data class TargetResolution(
        val fileName: String,
        val alreadyVerified: Boolean,
    )

    private fun getOrLoadDirIndex(
        share: DiskShare,
        normDir: String,
    ): MutableMap<String, Pair<String, CachedRemoteFile>> {
        dirCache[normDir]?.let { return it }
        touchActivity()
        val index = HashMap<String, Pair<String, CachedRemoteFile>>()
        val entries = runCatching { share.list(normDir) }.getOrNull()
        touchActivity()
        if (entries != null) {
            for (entry in entries) {
                val name = entry.fileName ?: continue
                if (name == "." || name == ".." || name.endsWith(".uback.tmp")) continue
                val isDir = (entry.fileAttributes and FileAttributes.FILE_ATTRIBUTE_DIRECTORY.value) != 0L
                if (isDir) continue
                index[name.lowercase()] = name to CachedRemoteFile(sizeBytes = entry.endOfFile)
            }
            dirCache[normDir] = index
        }
        return index
    }

    private fun recordVerifiedRemoteFile(
        normDir: String,
        fileName: String,
        sizeBytes: Long,
        sha256: String,
    ) {
        val dirIndex = dirCache.getOrPut(normDir) { HashMap() }
        dirIndex[fileName.lowercase()] = fileName to CachedRemoteFile(sizeBytes = sizeBytes, sha256 = sha256)
    }

    private fun resolveTargetFileName(
        share: DiskShare,
        normDir: String,
        originalFileName: String,
        localSize: Long,
        localSha256: String,
        bufferSize: Int,
        onStage: (String) -> Unit,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit,
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit,
    ): TargetResolution {
        val dirIndex = getOrLoadDirIndex(share, normDir)
        val checkedNames = HashSet<String>()
        val origKey = originalFileName.lowercase()
        val origEntry = dirIndex[origKey]
        val originalExists = origEntry != null || safeFileExists(share, joinSmbPath(normDir, originalFileName))
        if (originalExists) {
            checkedNames.add(origKey)
            onStage("verifying")
            val candidatePath = joinSmbPath(normDir, originalFileName)
            val existingSize = origEntry?.second?.sizeBytes ?: getRemoteFileSize(share, candidatePath)
            if (existingSize == localSize) {
                val existingHash = origEntry?.second?.sha256
                    ?: computeRemoteSha256(
                        share = share,
                        remotePath = candidatePath,
                        expectedSize = existingSize,
                        bufferSize = bufferSize,
                        onFileBytesProgress = onFileBytesProgress,
                        isCancelled = isCancelled,
                        waitIfPaused = waitIfPaused,
                    ).also {
                        recordVerifiedRemoteFile(normDir, originalFileName, existingSize, it)
                    }
                if (existingHash.equals(localSha256, ignoreCase = true)) {
                    return TargetResolution(originalFileName, alreadyVerified = true)
                }
            }
        }

        // Check disambiguated filename if original had different content
        val disambiguated = disambiguateFileName(originalFileName, localSha256.take(8))
        if (originalExists) {
            val disambKey = disambiguated.lowercase()
            checkedNames.add(disambKey)
            val disambEntry = dirIndex[disambKey]
            val disambPath = joinSmbPath(normDir, disambiguated)
            if (disambEntry != null || safeFileExists(share, disambPath)) {
                onStage("verifying")
                val disambSize = disambEntry?.second?.sizeBytes ?: getRemoteFileSize(share, disambPath)
                if (disambSize == localSize) {
                    val disambHash = disambEntry?.second?.sha256
                        ?: computeRemoteSha256(
                            share = share,
                            remotePath = disambPath,
                            expectedSize = disambSize,
                            bufferSize = bufferSize,
                            onFileBytesProgress = onFileBytesProgress,
                            isCancelled = isCancelled,
                            waitIfPaused = waitIfPaused,
                        ).also {
                            recordVerifiedRemoteFile(normDir, disambiguated, disambSize, it)
                        }
                    if (disambHash.equals(localSha256, ignoreCase = true)) {
                        return TargetResolution(disambiguated, alreadyVerified = true)
                    }
                }
            }
        }

        // Content-hash deduplication: never copy a file if another file in the same
        // destination folder already has the exact same size and SHA-256 hash.
        val existingMatch = findMatchingHashInDirectory(
            share = share,
            normDir = normDir,
            dirIndex = dirIndex,
            localSize = localSize,
            localSha256 = localSha256,
            bufferSize = bufferSize,
            skipLowerNames = checkedNames,
            onStage = onStage,
            onFileBytesProgress = onFileBytesProgress,
            isCancelled = isCancelled,
            waitIfPaused = waitIfPaused,
        )
        if (existingMatch != null) {
            return TargetResolution(existingMatch, alreadyVerified = true)
        }

        return TargetResolution(
            fileName = if (originalExists) disambiguated else originalFileName,
            alreadyVerified = false,
        )
    }

    private fun findMatchingHashInDirectory(
        share: DiskShare,
        normDir: String,
        dirIndex: MutableMap<String, Pair<String, CachedRemoteFile>>,
        localSize: Long,
        localSha256: String,
        bufferSize: Int,
        skipLowerNames: Set<String>,
        onStage: (String) -> Unit,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit,
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit,
    ): String? {
        for ((lowerName, pair) in dirIndex) {
            waitIfPaused()
            if (isCancelled()) throw InterruptedException("Backup cancelled during hash check")
            if (lowerName in skipLowerNames) continue
            val (actualName, cached) = pair
            if (cached.sizeBytes != localSize) continue

            onStage("verifying")
            val remotePath = joinSmbPath(normDir, actualName)
            val hash = cached.sha256 ?: runCatching {
                computeRemoteSha256(
                    share = share,
                    remotePath = remotePath,
                    expectedSize = localSize,
                    bufferSize = bufferSize,
                    onFileBytesProgress = onFileBytesProgress,
                    isCancelled = isCancelled,
                    waitIfPaused = waitIfPaused,
                )
            }.getOrNull()?.also { cached.sha256 = it } ?: continue
            if (hash.equals(localSha256, ignoreCase = true)) {
                return actualName
            }
        }
        return null
    }

    private fun uploadStream(
        share: DiskShare,
        localFile: File,
        localSize: Long,
        remotePath: String,
        resumeOffset: Long = 0L,
        bufferSize: Int,
        computeHashOnTheFly: Boolean,
        onBytesProgress: (Long) -> Unit,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit,
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit,
    ): String {
        val buffer = ByteArray(bufferSize)
        val digest = if (computeHashOnTheFly) MessageDigest.getInstance("SHA-256") else null
        var uploaded = resumeOffset
        var lastEmitMs = 0L
        val disposition = if (resumeOffset > 0L) {
            SMB2CreateDisposition.FILE_OPEN_IF
        } else {
            SMB2CreateDisposition.FILE_OVERWRITE_IF
        }

        share.openFile(
            remotePath,
            EnumSet.of(AccessMask.GENERIC_WRITE, AccessMask.DELETE),
            EnumSet.of(FileAttributes.FILE_ATTRIBUTE_NORMAL),
            SMB2ShareAccess.ALL,
            disposition,
            EnumSet.of(SMB2CreateOptions.FILE_NON_DIRECTORY_FILE),
        ).use { remoteFile ->
            FileInputStream(localFile).use { input ->
                if (resumeOffset > 0L) {
                    skipLocalFully(input, resumeOffset, digest, buffer)
                }
                while (true) {
                    waitIfPaused()
                    if (isCancelled()) {
                        // Keep partial `.uback.tmp` intact on NAS so "Continue From Last Stop"
                        // can resume this large file from [uploaded] bytes!
                        throw InterruptedException("Backup cancelled during upload")
                    }
                    val read = readChunkFully(input, buffer)
                    if (read <= 0) break
                    touchActivity()
                    digest?.update(buffer, 0, read)
                    // smbj automatically pipelines multiple SMB2 WRITE credits across [read] bytes!
                    remoteFile.write(buffer, uploaded, 0, read)
                    touchActivity()
                    uploaded += read
                    val now = SystemClock.elapsedRealtime()
                    if (uploaded >= localSize || now - lastEmitMs >= 120L) {
                        lastEmitMs = now
                        onBytesProgress(uploaded)
                        onFileBytesProgress("uploading", uploaded, localSize)
                    }
                }
                touchActivity()
            }
        }
        return digest?.digest()?.toHexString().orEmpty()
    }

    /**
     * Fills [buffer] up to its capacity (or until EOF) so `smbj` receives a full dynamic
     * chunk (`64 KB` .. `4 MB`) and can pipeline multiple SMB2 WRITE requests in parallel.
     */
    private fun readChunkFully(input: FileInputStream, buffer: ByteArray): Int {
        var totalRead = 0
        while (totalRead < buffer.size) {
            val n = input.read(buffer, totalRead, buffer.size - totalRead)
            if (n <= 0) break
            totalRead += n
        }
        return totalRead
    }

    private fun skipLocalFully(
        input: FileInputStream,
        bytesToSkip: Long,
        digest: MessageDigest?,
        scratchBuffer: ByteArray,
    ) {
        var remaining = bytesToSkip
        if (digest != null) {
            while (remaining > 0L) {
                val toRead = minOf(scratchBuffer.size.toLong(), remaining).toInt()
                val n = input.read(scratchBuffer, 0, toRead)
                if (n <= 0) {
                    throw IllegalStateException("Unexpected EOF hashing resumed prefix ($bytesToSkip bytes)")
                }
                touchActivity()
                digest.update(scratchBuffer, 0, n)
                remaining -= n
            }
            return
        }
        while (remaining > 0L) {
            val skipped = input.skip(remaining)
            if (skipped <= 0L) {
                if (input.read() < 0) {
                    throw IllegalStateException("Unexpected EOF seeking to resume offset $bytesToSkip")
                }
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }

    private fun getRemoteFileSize(share: DiskShare, remotePath: String): Long {
        return share.getFileInformation(remotePath).standardInformation.endOfFile
    }

    private fun computeRemoteSha256(
        share: DiskShare,
        remotePath: String,
        expectedSize: Long,
        bufferSize: Int,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit,
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(bufferSize)
        var lastEmitMs = 0L
        onFileBytesProgress("verifying", 0L, expectedSize)
        share.openFile(
            remotePath,
            EnumSet.of(AccessMask.GENERIC_READ),
            null,
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OPEN,
            null,
        ).use { remoteFile ->
            var offset = 0L
            while (offset < expectedSize) {
                waitIfPaused()
                if (isCancelled()) throw InterruptedException("Backup cancelled during verification")
                val toRead = minOf(buffer.size.toLong(), expectedSize - offset).toInt()
                touchActivity()
                val read = remoteFile.read(buffer, offset, 0, toRead)
                touchActivity()
                if (read <= 0) {
                    throw IllegalStateException(
                        "Unexpected EOF reading $remotePath at offset $offset / $expectedSize",
                    )
                }
                digest.update(buffer, 0, read)
                offset += read
                val now = SystemClock.elapsedRealtime()
                if (offset >= expectedSize || now - lastEmitMs >= 120L) {
                    lastEmitMs = now
                    onFileBytesProgress("verifying", offset, expectedSize)
                }
            }
        }
        return digest.digest().toHexString()
    }

    private fun computeLocalSha256(
        localFile: File,
        totalSize: Long,
        bufferSize: Int,
        onFileBytesProgress: (stage: String, processedBytes: Long, fileTotalBytes: Long) -> Unit,
        isCancelled: () -> Boolean,
        waitIfPaused: () -> Unit,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(bufferSize)
        var hashed = 0L
        var lastEmitMs = 0L
        FileInputStream(localFile).use { input ->
            while (true) {
                waitIfPaused()
                if (isCancelled()) throw InterruptedException("Backup cancelled during hashing")
                val read = input.read(buffer)
                if (read <= 0) break
                touchActivity()
                digest.update(buffer, 0, read)
                hashed += read
                val now = SystemClock.elapsedRealtime()
                if (hashed >= totalSize || now - lastEmitMs >= 150L) {
                    lastEmitMs = now
                    onFileBytesProgress("hashing", hashed, totalSize)
                }
            }
        }
        return digest.digest().toHexString()
    }

    private fun renameRemoteFile(share: DiskShare, fromPath: String, toPath: String) {
        share.openFile(
            fromPath,
            EnumSet.of(AccessMask.DELETE, AccessMask.GENERIC_WRITE),
            null,
            SMB2ShareAccess.ALL,
            SMB2CreateDisposition.FILE_OPEN,
            null,
        ).use { file ->
            file.rename(toPath, true)
        }
    }

    private fun setRemoteLastModified(share: DiskShare, remotePath: String, epochMs: Long) {
        val ft = FileTime.ofEpochMillis(epochMs)
        val info = FileBasicInformation(ft, ft, ft, ft, FileAttributes.FILE_ATTRIBUTE_NORMAL.value)
        share.setFileInformation(remotePath, info)
    }

    private fun ensureDirectories(share: DiskShare, smbDirPath: String) {
        if (smbDirPath.isBlank() || smbDirPath in ensuredDirs) return
        val segments = smbDirPath.split('\\').filter { it.isNotBlank() }
        var current = ""
        for (segment in segments) {
            current = if (current.isEmpty()) segment else "$current\\$segment"
            if (current in ensuredDirs) continue
            touchActivity()
            if (!safeFolderExists(share, current)) {
                try {
                    share.mkdir(current)
                } catch (e: SMBApiException) {
                    if (e.status != NtStatus.STATUS_OBJECT_NAME_COLLISION) throw e
                }
            }
            ensuredDirs.add(current)
            touchActivity()
        }
    }

    private fun safeFolderExists(share: DiskShare, path: String): Boolean {
        return try {
            share.folderExists(path)
        } catch (e: SMBApiException) {
            if (isNotFoundStatus(e)) false else throw e
        }
    }

    private fun safeFileExists(share: DiskShare, path: String): Boolean {
        return try {
            share.fileExists(path)
        } catch (e: SMBApiException) {
            if (isNotFoundStatus(e)) false else throw e
        }
    }

    private fun isNotFoundStatus(e: SMBApiException): Boolean {
        return e.status == NtStatus.STATUS_NO_SUCH_FILE ||
            e.status == NtStatus.STATUS_OBJECT_NAME_NOT_FOUND ||
            e.status == NtStatus.STATUS_OBJECT_PATH_NOT_FOUND
    }

    private fun closeConnectionOnly() {
        runCatching { diskShare?.close() }
        runCatching { session?.close() }
        runCatching { connection?.close() }
        runCatching { client?.close() }
        diskShare = null
        session = null
        connection = null
        client = null
    }

    override fun close() {
        closeConnectionOnly()
        ensuredDirs.clear()
        dirCache.clear()
    }

    companion object {
        const val MIN_BUFFER_SIZE = 64 * 1024            // 64 KB for small files (< 256 KB)
        const val MEDIUM_BUFFER_SIZE = 256 * 1024        // 256 KB for medium files (256 KB .. < 8 MB)
        const val LARGE_BUFFER_SIZE = 1024 * 1024        // 1 MB for large files (8 MB .. < 64 MB)
        const val HUGE_BUFFER_SIZE = 4 * 1024 * 1024     // 4 MB for huge files (>= 64 MB, e.g. WhatsApp DBs & 4K videos)

        /**
         * Dynamically selects the optimal SMB2 / disk I/O chunk buffer size for [fileSizeBytes].
         */
        fun selectDynamicBufferSize(fileSizeBytes: Long): Int = when {
            fileSizeBytes >= 64L * 1024L * 1024L -> HUGE_BUFFER_SIZE
            fileSizeBytes >= 8L * 1024L * 1024L -> LARGE_BUFFER_SIZE
            fileSizeBytes >= 256L * 1024L -> MEDIUM_BUFFER_SIZE
            else -> MIN_BUFFER_SIZE
        }

        fun normalizeSmbPath(path: String): String = path
            .replace('/', '\\')
            .split('\\')
            .filter { it.isNotBlank() }
            .joinToString("\\")

        fun joinSmbPath(dir: String, name: String): String =
            if (dir.isBlank()) name else "$dir\\$name"

        fun disambiguateFileName(fileName: String, shortHash: String): String {
            val dot = fileName.lastIndexOf('.')
            return if (dot > 0 && dot < fileName.length - 1) {
                "${fileName.substring(0, dot)}_$shortHash${fileName.substring(dot)}"
            } else {
                "${fileName}_$shortHash"
            }
        }

        private fun ByteArray.toHexString(): String = joinToString("") { "%02x".format(it) }
    }
}
