package uback.rodvieirasilva.github.io

import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.Inflater
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Pure-Kotlin streaming decryptor for WhatsApp End-to-End Encrypted `.crypt15` backups
 * using a user-supplied 64-character hex encryption key (no root required).
 *
 * Implements the standard WhatsApp Crypt15 format:
 * 1. Protobuf varint length + `BackupPrefix` protobuf carrying `C15IV` (field 3 -> field 1, 16-byte IV).
 * 2. HMAC-SHA256 key derivation (`encryptionloop` with `"backup encryption"` + `0x01`).
 * 3. Optional trailing 16-byte MD5 checksum verification.
 * 4. Streaming AES-256-GCM authenticated decryption + zlib inflation to plaintext SQLite DB.
 */
object WhatsAppCrypt15Decryptor {

    private const val BUFFER_SIZE = 64 * 1024
    private const val GCM_TAG_BITS = 128
    private const val GCM_TAG_BYTES = 16
    private const val MD5_BYTES = 16
    private val BACKUP_ENCRYPTION_MSG = "backup encryption".toByteArray(Charsets.UTF_8)
    private val SQLITE_MAGIC = "SQLite format 3".toByteArray(Charsets.US_ASCII)

    fun normalizeHexKey(raw: String?): String? {
        if (raw == null) return null
        val cleaned = raw.replace(Regex("[\\s-]+"), "").lowercase()
        if (cleaned.length != 64) return null
        if (!cleaned.all { it in '0'..'9' || it in 'a'..'f' }) return null
        return cleaned
    }

    fun deriveAesKey(hexKey64: String): ByteArray {
        val norm = normalizeHexKey(hexKey64)
            ?: throw IllegalArgumentException("WhatsApp backup key must be 64 hex characters.")
        val rootKey = hexToBytes(norm)
        val privateKey = hmacSha256(ByteArray(32), rootKey)
        val msg = ByteArray(BACKUP_ENCRYPTION_MSG.size + 1)
        System.arraycopy(BACKUP_ENCRYPTION_MSG, 0, msg, 0, BACKUP_ENCRYPTION_MSG.size)
        msg[BACKUP_ENCRYPTION_MSG.size] = 0x01
        return hmacSha256(privateKey, msg)
    }

    /**
     * Streams and decrypts [encryptedFile] (`.crypt15`) into [outputSqliteFile], verifying both
     * the AES-256-GCM authentication tag and the resulting SQLite header.
     */
    fun decryptToSqliteFile(
        encryptedFile: File,
        hexKey64: String,
        outputSqliteFile: File,
    ) {
        val aesKey = deriveAesKey(hexKey64)
        val fileLen = encryptedFile.length()
        require(fileLen > 48L) { "File too small to be a valid .crypt15 backup: ${encryptedFile.name}" }

        // 1. Parse varint length + BackupPrefix protobuf header & compute MD5 over [0 .. fileLen - 16)
        val header = readHeaderAndCheckMd5(encryptedFile, fileLen)
        val ciphertextEnd = if (header.hasMd5Footer) fileLen - MD5_BYTES else fileLen
        val cipherBytesTotal = ciphertextEnd - header.dataOffset
        require(cipherBytesTotal > GCM_TAG_BYTES) { "Invalid .crypt15 payload length" }

        // 2. Streaming AES-256-GCM decryption + zlib decompression
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, SecretKeySpec(aesKey, "AES"), GCMParameterSpec(GCM_TAG_BITS, header.iv))
        }
        val inflater = Inflater()
        val inBuf = ByteArray(BUFFER_SIZE)
        val inflateBuf = ByteArray(BUFFER_SIZE)

        outputSqliteFile.parentFile?.mkdirs()
        try {
            BufferedInputStream(FileInputStream(encryptedFile), BUFFER_SIZE).use { input ->
                skipFully(input, header.dataOffset)
                BufferedOutputStream(FileOutputStream(outputSqliteFile), BUFFER_SIZE).use { output ->
                    var remaining = cipherBytesTotal
                    while (remaining > 0L) {
                        val toRead = minOf(inBuf.size.toLong(), remaining).toInt()
                        val read = input.read(inBuf, 0, toRead)
                        if (read <= 0) break
                        remaining -= read
                        val plainChunk = cipher.update(inBuf, 0, read)
                        if (plainChunk != null && plainChunk.isNotEmpty()) {
                            inflateChunk(inflater, plainChunk, inflateBuf, output)
                        }
                    }
                    // Verifies the 128-bit GCM authentication tag and emits final plaintext bytes.
                    val finalChunk = cipher.doFinal()
                    if (finalChunk != null && finalChunk.isNotEmpty()) {
                        inflateChunk(inflater, finalChunk, inflateBuf, output)
                    }
                    output.flush()
                }
            }
        } catch (e: Throwable) {
            runCatching { outputSqliteFile.delete() }
            throw e
        } finally {
            inflater.end()
        }

        // 3. Validate plaintext SQLite magic header
        val magic = ByteArray(SQLITE_MAGIC.size)
        FileInputStream(outputSqliteFile).use { input ->
            if (input.read(magic) != SQLITE_MAGIC.size || !magic.contentEquals(SQLITE_MAGIC)) {
                runCatching { outputSqliteFile.delete() }
                throw IllegalStateException("Decrypted payload is not a valid SQLite database.")
            }
        }
    }

    private data class ParsedHeader(
        val iv: ByteArray,
        val dataOffset: Long,
        val hasMd5Footer: Boolean,
    )

    private fun readHeaderAndCheckMd5(file: File, fileLen: Long): ParsedHeader {
        val md5 = MessageDigest.getInstance("MD5")
        var dataOffset = 0L
        lateinit var headerBytes: ByteArray

        BufferedInputStream(FileInputStream(file), BUFFER_SIZE).use { input ->
            // Read protobuf varint size of BackupPrefix
            var protobufSize = 0
            var shift = 0
            while (shift < 35) {
                val b = input.read()
                if (b < 0) throw IllegalStateException("Unexpected EOF reading .crypt15 header size")
                md5.update(b.toByte())
                dataOffset++
                protobufSize = protobufSize or ((b and 0x7F) shl shift)
                if ((b and 0x80) == 0) break
                shift += 7
            }
            require(protobufSize in 1..65536) { "Unexpected .crypt15 protobuf header size: $protobufSize" }

            headerBytes = ByteArray(protobufSize)
            readFully(input, headerBytes)
            md5.update(headerBytes)
            dataOffset += protobufSize

            // Feed remaining bytes up to (fileLen - 16) into MD5, then read trailing 16 bytes
            val bodyLen = fileLen - dataOffset - MD5_BYTES
            val buf = ByteArray(BUFFER_SIZE)
            var rem = bodyLen
            while (rem > 0L) {
                val n = input.read(buf, 0, minOf(buf.size.toLong(), rem).toInt())
                if (n <= 0) break
                md5.update(buf, 0, n)
                rem -= n
            }
            val trailing16 = ByteArray(MD5_BYTES)
            readFully(input, trailing16)
            val hasMd5 = md5.digest().contentEquals(trailing16)
            val iv = extractC15Iv(headerBytes)
                ?: throw IllegalStateException("Could not locate 16-byte C15IV in .crypt15 header")
            return ParsedHeader(iv = iv, dataOffset = dataOffset, hasMd5Footer = hasMd5)
        }
    }

    /**
     * Minimal protobuf wire parser for `BackupPrefix` (field 3: `C15IV` -> field 1: `encryption_iv`).
     */
    internal fun extractC15Iv(prefixBytes: ByteArray): ByteArray? {
        val c15Message = findLengthDelimitedField(prefixBytes, targetFieldNumber = 3) ?: return null
        val iv = findLengthDelimitedField(c15Message, targetFieldNumber = 1) ?: return null
        return if (iv.size == 16) iv else null
    }

    private fun findLengthDelimitedField(data: ByteArray, targetFieldNumber: Int): ByteArray? {
        var pos = 0
        while (pos < data.size) {
            val (tag, nextPos) = readVarint(data, pos) ?: return null
            pos = nextPos
            val fieldNumber = (tag ushr 3).toInt()
            val wireType = (tag and 0x07L).toInt()
            when (wireType) {
                0 -> { // Varint
                    val (_, after) = readVarint(data, pos) ?: return null
                    pos = after
                }
                1 -> pos += 8 // 64-bit
                2 -> { // Length-delimited
                    val (lenLong, afterLen) = readVarint(data, pos) ?: return null
                    val len = lenLong.toInt()
                    if (len < 0 || afterLen + len > data.size) return null
                    if (fieldNumber == targetFieldNumber) {
                        return data.copyOfRange(afterLen, afterLen + len)
                    }
                    pos = afterLen + len
                }
                5 -> pos += 4 // 32-bit
                else -> return null
            }
        }
        return null
    }

    private fun readVarint(data: ByteArray, start: Int): Pair<Long, Int>? {
        var result = 0L
        var shift = 0
        var pos = start
        while (pos < data.size && shift < 64) {
            val b = data[pos++].toInt() and 0xFF
            result = result or ((b and 0x7F).toLong() shl shift)
            if ((b and 0x80) == 0) return result to pos
            shift += 7
        }
        return null
    }

    private fun inflateChunk(
        inflater: Inflater,
        input: ByteArray,
        outBuf: ByteArray,
        output: BufferedOutputStream,
    ) {
        inflater.setInput(input)
        while (!inflater.needsInput() && !inflater.finished()) {
            val count = inflater.inflate(outBuf)
            if (count > 0) {
                output.write(outBuf, 0, count)
            } else if (inflater.needsDictionary()) {
                throw IllegalStateException("Unexpected zlib dictionary in .crypt15 payload")
            } else {
                break
            }
        }
    }

    private fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }

    private fun hexToBytes(hex: String): ByteArray {
        val out = ByteArray(hex.length / 2)
        for (i in out.indices) {
            out[i] = ((hex[i * 2].digitToInt(16) shl 4) or hex[i * 2 + 1].digitToInt(16)).toByte()
        }
        return out
    }

    private fun readFully(input: InputStream, dest: ByteArray) {
        var offset = 0
        while (offset < dest.size) {
            val n = input.read(dest, offset, dest.size - offset)
            if (n <= 0) throw IllegalStateException("Unexpected EOF reading .crypt15")
            offset += n
        }
    }

    private fun skipFully(input: InputStream, bytesToSkip: Long) {
        var remaining = bytesToSkip
        while (remaining > 0L) {
            val skipped = input.skip(remaining)
            if (skipped <= 0L) {
                if (input.read() < 0) throw IllegalStateException("Unexpected EOF skipping header")
                remaining--
            } else {
                remaining -= skipped
            }
        }
    }
}
