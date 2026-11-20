package uback.rodvieirasilva.github.io

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Generates lightweight read-only snapshot files (Contacts `.vcf`, SMS `.json`, Call Logs `.json`)
 * inside app cache so they can be transferred and SHA-256 verified over SMB without ever deleting
 * real user contacts, messages, or call history in Crop Mode.
 */
object SnapshotExporter {

    private val dateFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

    fun estimateStats(context: Context): Map<String, Map<String, Any>> {
        return mapOf(
            "snapshots.contacts" to estimateContacts(context),
            "snapshots.sms" to estimateSms(context),
            "snapshots.call_logs" to estimateCallLogs(context),
        )
    }

    fun exportEnabledSnapshots(
        context: Context,
        enabledSources: Set<String>,
    ): List<DiscoveredMediaItem> {
        val out = mutableListOf<DiscoveredMediaItem>()
        val cacheDir = File(context.cacheDir, "uback_snapshots").apply { mkdirs() }
        val stamp = LocalDate.now().format(dateFmt)
        val nowMs = System.currentTimeMillis()

        if ("snapshots.contacts" in enabledSources && hasPerm(context, Manifest.permission.READ_CONTACTS)) {
            runCatching { exportContactsVcf(context, cacheDir, stamp, nowMs) }
                .getOrNull()?.let { out.add(it) }
        }
        if ("snapshots.sms" in enabledSources && hasPerm(context, Manifest.permission.READ_SMS)) {
            runCatching { exportSmsJson(context, cacheDir, stamp, nowMs) }
                .getOrNull()?.let { out.add(it) }
        }
        if ("snapshots.call_logs" in enabledSources && hasPerm(context, Manifest.permission.READ_CALL_LOG)) {
            runCatching { exportCallLogsJson(context, cacheDir, stamp, nowMs) }
                .getOrNull()?.let { out.add(it) }
        }
        return out
    }

    private fun estimateContacts(context: Context): Map<String, Any> {
        if (!hasPerm(context, Manifest.permission.READ_CONTACTS)) {
            return mapOf("count" to 0, "totalBytes" to 0L)
        }
        val rows = queryRowCount(context, ContactsContract.Contacts.CONTENT_URI)
        return if (rows > 0) mapOf("count" to 1, "totalBytes" to rows * 256L)
        else mapOf("count" to 0, "totalBytes" to 0L)
    }

    private fun estimateSms(context: Context): Map<String, Any> {
        if (!hasPerm(context, Manifest.permission.READ_SMS)) {
            return mapOf("count" to 0, "totalBytes" to 0L)
        }
        val rows = queryRowCount(context, Telephony.Sms.CONTENT_URI)
        return if (rows > 0) mapOf("count" to 1, "totalBytes" to rows * 220L)
        else mapOf("count" to 0, "totalBytes" to 0L)
    }

    private fun estimateCallLogs(context: Context): Map<String, Any> {
        if (!hasPerm(context, Manifest.permission.READ_CALL_LOG)) {
            return mapOf("count" to 0, "totalBytes" to 0L)
        }
        val rows = queryRowCount(context, CallLog.Calls.CONTENT_URI)
        return if (rows > 0) mapOf("count" to 1, "totalBytes" to rows * 160L)
        else mapOf("count" to 0, "totalBytes" to 0L)
    }

    private fun queryRowCount(context: Context, uri: Uri): Int {
        return runCatching {
            context.contentResolver.query(uri, arrayOf("_id"), null, null, null)?.use { it.count } ?: 0
        }.getOrDefault(0)
    }

    private fun exportContactsVcf(
        context: Context,
        cacheDir: File,
        stamp: String,
        nowMs: Long,
    ): DiscoveredMediaItem? {
        val lookupKeys = mutableListOf<String>()
        context.contentResolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts.LOOKUP_KEY),
            null,
            null,
            null,
        )?.use { cursor ->
            val idx = cursor.getColumnIndex(ContactsContract.Contacts.LOOKUP_KEY)
            while (cursor.moveToNext()) {
                val key = if (idx >= 0) cursor.getString(idx) else null
                if (!key.isNullOrBlank()) lookupKeys.add(key)
            }
        }
        if (lookupKeys.isEmpty()) return null

        val outFile = File(cacheDir, "contacts_$stamp.vcf")
        outFile.outputStream().buffered().use { out ->
            for (key in lookupKeys) {
                val vcardUri = Uri.withAppendedPath(ContactsContract.Contacts.CONTENT_VCARD_URI, key)
                runCatching {
                    context.contentResolver.openInputStream(vcardUri)?.use { input ->
                        input.copyTo(out)
                        out.write('\n'.code)
                    }
                }
            }
            out.flush()
        }
        if (outFile.length() <= 0L) return null
        return DiscoveredMediaItem(
            id = "snapshot_contacts_$stamp",
            contentUri = null,
            fileName = outFile.name,
            localPath = outFile.absolutePath,
            sourceId = "snapshots.contacts",
            sourceFolder = "snapshots/contacts",
            sizeBytes = outFile.length(),
            createdAtMs = nowMs,
            mimeType = "text/vcard",
            isSnapshot = true,
        )
    }

    private fun exportSmsJson(
        context: Context,
        cacheDir: File,
        stamp: String,
        nowMs: Long,
    ): DiscoveredMediaItem? {
        val array = JSONArray()
        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE,
            ),
            null,
            null,
            "${Telephony.Sms.DATE} ASC",
        )?.use { cursor ->
            val addrIdx = cursor.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIdx = cursor.getColumnIndex(Telephony.Sms.BODY)
            val dateIdx = cursor.getColumnIndex(Telephony.Sms.DATE)
            val typeIdx = cursor.getColumnIndex(Telephony.Sms.TYPE)
            while (cursor.moveToNext()) {
                val obj = JSONObject()
                obj.put("address", if (addrIdx >= 0) cursor.getString(addrIdx) ?: "" else "")
                obj.put("body", if (bodyIdx >= 0) cursor.getString(bodyIdx) ?: "" else "")
                obj.put("dateMs", if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L)
                obj.put("type", if (typeIdx >= 0) cursor.getInt(typeIdx) else 0)
                array.put(obj)
            }
        }
        if (array.length() == 0) return null

        val outFile = File(cacheDir, "sms_$stamp.json")
        outFile.writeText(array.toString(2))
        return DiscoveredMediaItem(
            id = "snapshot_sms_$stamp",
            contentUri = null,
            fileName = outFile.name,
            localPath = outFile.absolutePath,
            sourceId = "snapshots.sms",
            sourceFolder = "snapshots/sms",
            sizeBytes = outFile.length(),
            createdAtMs = nowMs,
            mimeType = "application/json",
            isSnapshot = true,
        )
    }

    private fun exportCallLogsJson(
        context: Context,
        cacheDir: File,
        stamp: String,
        nowMs: Long,
    ): DiscoveredMediaItem? {
        val array = JSONArray()
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.TYPE,
            ),
            null,
            null,
            "${CallLog.Calls.DATE} ASC",
        )?.use { cursor ->
            val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
            val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
            val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
            val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)
            val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
            while (cursor.moveToNext()) {
                val obj = JSONObject()
                obj.put("number", if (numIdx >= 0) cursor.getString(numIdx) ?: "" else "")
                obj.put("name", if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else "")
                obj.put("dateMs", if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L)
                obj.put("durationSec", if (durIdx >= 0) cursor.getLong(durIdx) else 0L)
                obj.put("type", if (typeIdx >= 0) cursor.getInt(typeIdx) else 0)
                array.put(obj)
            }
        }
        if (array.length() == 0) return null

        val outFile = File(cacheDir, "call_logs_$stamp.json")
        outFile.writeText(array.toString(2))
        return DiscoveredMediaItem(
            id = "snapshot_calls_$stamp",
            contentUri = null,
            fileName = outFile.name,
            localPath = outFile.absolutePath,
            sourceId = "snapshots.call_logs",
            sourceFolder = "snapshots/call-logs",
            sizeBytes = outFile.length(),
            createdAtMs = nowMs,
            mimeType = "application/json",
            isSnapshot = true,
        )
    }

    private fun hasPerm(context: Context, perm: String): Boolean =
        ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
}
