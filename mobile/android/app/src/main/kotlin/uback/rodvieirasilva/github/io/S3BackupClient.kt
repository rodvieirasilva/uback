package uback.rodvieirasilva.github.io

import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Lightweight, zero-SDK S3 / S3-compatible client using AWS Signature Version 4 (SigV4).
 * Works with MinIO, Garage, Backblaze B2, Cloudflare R2, AWS S3, and any S3-compatible endpoint.
 *
 * Enforces UBack's non-negotiable data safety invariant:
 * - Pre-flight HEAD check for idempotent skip when remote SHA-256 & size already match
 * - PUT upload with `x-amz-content-sha256` and `x-amz-meta-uback-sha256`
 * - Full streaming GET read-back SHA-256 verification before returning success
 */
object S3BackupClient {
    private const val TAG = "UBack"
    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 60_000

    data class S3Config(
        val endpoint: String,
        val region: String,
        val bucket: String,
        val prefix: String,
        val accessKey: String,
        val secretKey: String,
    ) {
        fun normalizedEndpoint(): String = endpoint.trim().trimEnd('/')
        fun normalizedRegion(): String = region.trim().ifEmpty { "us-east-1" }
        fun normalizedBucket(): String = bucket.trim().trim('/')
        fun normalizedPrefix(): String = prefix.trim().trim('/')
    }

    data class UploadOutcome(
        val skipped: Boolean,
        val sha256: String,
        val bytesTransferred: Long,
    )

    fun testConnection(cfg: S3Config): Pair<Boolean, String> {
        if (cfg.normalizedEndpoint().isEmpty() || cfg.normalizedBucket().isEmpty()) {
            return false to "S3 endpoint and bucket are required."
        }
        return try {
            val path = "/${cfg.normalizedBucket()}"
            val conn = openSignedConnection(
                cfg = cfg,
                method = "HEAD",
                canonicalUri = path,
                payloadSha256 = sha256Hex(ByteArray(0)),
            )
            val code = conn.responseCode
            conn.disconnect()
            if (code in 200..299) {
                true to "Connected to S3 bucket '${cfg.normalizedBucket()}' (${cfg.normalizedEndpoint()})"
            } else {
                false to "S3 bucket check failed (HTTP $code)"
            }
        } catch (e: Exception) {
            false to "S3 connection error: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    fun buildObjectKey(cfg: S3Config, relativePath: String): String {
        val cleanRel = relativePath.trim().replace('\\', '/').trim('/')
        val p = cfg.normalizedPrefix()
        return if (p.isEmpty()) cleanRel else "$p/$cleanRel"
    }

    fun uploadAndVerify(
        cfg: S3Config,
        localFile: File,
        relativePath: String,
        onProgress: (Long) -> Unit = {},
        isCancelled: () -> Boolean = { false },
    ): UploadOutcome {
        val localSize = localFile.length()
        val localSha = computeFileSha256(localFile)
        val key = buildObjectKey(cfg, relativePath)
        val encodedPath = "/${cfg.normalizedBucket()}/${encodePathSegments(key)}"

        // 1. Pre-flight HEAD check for exact remote SHA-256 match
        val headConn = openSignedConnection(
            cfg = cfg,
            method = "HEAD",
            canonicalUri = encodedPath,
            payloadSha256 = sha256Hex(ByteArray(0)),
        )
        val headCode = headConn.responseCode
        val remoteSha = headConn.getHeaderField("x-amz-meta-uback-sha256")?.trim()
        val remoteLen = headConn.contentLengthLong
        headConn.disconnect()
        if (headCode == 200 && remoteSha.equals(localSha, ignoreCase = true) && remoteLen == localSize) {
            Log.i(TAG, "S3 skipped $key — SHA-256 already matched remote (0 bytes uploaded)")
            return UploadOutcome(skipped = true, sha256 = localSha, bytesTransferred = 0L)
        }

        if (isCancelled()) throw InterruptedException("Cancelled before S3 upload")

        // 2. Streaming PUT with SHA-256 content header + metadata
        val putConn = openSignedConnection(
            cfg = cfg,
            method = "PUT",
            canonicalUri = encodedPath,
            payloadSha256 = localSha,
            extraHeaders = mapOf("x-amz-meta-uback-sha256" to localSha),
            contentLength = localSize,
        )
        putConn.doOutput = true
        putConn.setFixedLengthStreamingMode(localSize)
        val buf = ByteArray(256 * 1024)
        var sent = 0L
        FileInputStream(localFile).use { input ->
            putConn.outputStream.use { out ->
                while (true) {
                    if (isCancelled()) throw InterruptedException("Cancelled during S3 upload")
                    val n = input.read(buf)
                    if (n <= 0) break
                    out.write(buf, 0, n)
                    sent += n
                    onProgress(sent)
                }
            }
        }
        val putCode = putConn.responseCode
        putConn.disconnect()
        if (putCode !in 200..299) {
            throw IllegalStateException("S3 PUT failed for $key (HTTP $putCode)")
        }

        // 3. Mandatory full streaming GET read-back SHA-256 verification
        val getConn = openSignedConnection(
            cfg = cfg,
            method = "GET",
            canonicalUri = encodedPath,
            payloadSha256 = sha256Hex(ByteArray(0)),
        )
        val getCode = getConn.responseCode
        if (getCode !in 200..299) {
            getConn.disconnect()
            throw IllegalStateException("S3 read-back GET failed for $key (HTTP $getCode)")
        }
        val digest = MessageDigest.getInstance("SHA-256")
        var readBackBytes = 0L
        getConn.inputStream.use { input ->
            while (true) {
                if (isCancelled()) throw InterruptedException("Cancelled during S3 read-back")
                val n = input.read(buf)
                if (n <= 0) break
                digest.update(buf, 0, n)
                readBackBytes += n
            }
        }
        getConn.disconnect()

        val remoteReadSha = digest.digest().joinToString("") { "%02x".format(it) }
        if (readBackBytes != localSize || !remoteReadSha.equals(localSha, ignoreCase = true)) {
            throw IllegalStateException(
                "S3 read-back SHA-256 mismatch for $key (expected $localSha/$localSize, got $remoteReadSha/$readBackBytes)",
            )
        }

        Log.i(TAG, "S3 verified & committed $key (sha256=${localSha.take(12)}...)")
        return UploadOutcome(skipped = false, sha256 = localSha, bytesTransferred = localSize)
    }

    private fun openSignedConnection(
        cfg: S3Config,
        method: String,
        canonicalUri: String,
        payloadSha256: String,
        extraHeaders: Map<String, String> = emptyMap(),
        contentLength: Long? = null,
    ): HttpURLConnection {
        val url = URL("${cfg.normalizedEndpoint()}$canonicalUri")
        val hostHeader = if (url.port != -1 && url.port != url.defaultPort) {
            "${url.host}:${url.port}"
        } else {
            url.host
        }
        val now = Date()
        val amzDate = utcFormat("yyyyMMdd'T'HHmmss'Z'", now)
        val dateStamp = utcFormat("yyyyMMdd", now)
        val region = cfg.normalizedRegion()

        val headers = sortedMapOf<String, String>(String.CASE_INSENSITIVE_ORDER)
        headers["host"] = hostHeader
        headers["x-amz-content-sha256"] = payloadSha256
        headers["x-amz-date"] = amzDate
        for ((k, v) in extraHeaders) {
            headers[k.lowercase(Locale.US)] = v.trim()
        }

        val canonicalHeaders = StringBuilder()
        val signedHeaderNames = mutableListOf<String>()
        for ((k, v) in headers) {
            val lk = k.lowercase(Locale.US)
            canonicalHeaders.append(lk).append(':').append(v).append('\n')
            signedHeaderNames.add(lk)
        }
        val signedHeadersStr = signedHeaderNames.joinToString(";")
        val canonicalRequest = listOf(
            method,
            canonicalUri,
            "",
            canonicalHeaders.toString(),
            signedHeadersStr,
            payloadSha256,
        ).joinToString("\n")

        val credentialScope = "$dateStamp/$region/s3/aws4_request"
        val stringToSign = listOf(
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            sha256Hex(canonicalRequest.toByteArray(Charsets.UTF_8)),
        ).joinToString("\n")

        val signingKey = getSignatureKey(cfg.secretKey, dateStamp, region, "s3")
        val signature = hmacSha256(signingKey, stringToSign).joinToString("") { "%02x".format(it) }
        val authHeader =
            "AWS4-HMAC-SHA256 Credential=${cfg.accessKey}/$credentialScope, SignedHeaders=$signedHeadersStr, Signature=$signature"

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            setRequestProperty("Host", hostHeader)
            setRequestProperty("x-amz-content-sha256", payloadSha256)
            setRequestProperty("x-amz-date", amzDate)
            setRequestProperty("Authorization", authHeader)
            if (contentLength != null) {
                setRequestProperty("Content-Length", contentLength.toString())
            }
            for ((k, v) in extraHeaders) {
                setRequestProperty(k, v)
            }
        }
        return conn
    }

    private fun computeFileSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(256 * 1024)
        FileInputStream(file).use { input ->
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun encodePathSegments(key: String): String =
        key.split('/').filter { it.isNotEmpty() }.joinToString("/") { seg ->
            URLEncoder.encode(seg, "UTF-8").replace("+", "%20")
        }

    private fun utcFormat(pattern: String, date: Date): String =
        SimpleDateFormat(pattern, Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(date)

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun hmacSha256(key: ByteArray, data: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data.toByteArray(Charsets.UTF_8))
    }

    private fun getSignatureKey(secretKey: String, dateStamp: String, region: String, service: String): ByteArray {
        val kDate = hmacSha256("AWS4$secretKey".toByteArray(Charsets.UTF_8), dateStamp)
        val kRegion = hmacSha256(kDate, region)
        val kService = hmacSha256(kRegion, service)
        return hmacSha256(kService, "aws4_request")
    }
}
