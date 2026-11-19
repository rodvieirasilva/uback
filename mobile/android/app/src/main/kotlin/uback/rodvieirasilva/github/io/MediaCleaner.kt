package uback.rodvieirasilva.github.io

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import java.io.File

object MediaCleaner {

    /**
     * Deletes a local media file strictly AFTER post-transfer verification succeeded.
     * Removes both the file on disk and the Android MediaStore index entry so Samsung Gallery
     * updates immediately without leaving ghost thumbnails.
     */
    fun deleteVerifiedFile(context: Context, localPath: String, contentUriStr: String?): Boolean {
        val file = File(localPath)
        var deletedOnDisk = !file.exists()

        if (file.exists()) {
            deletedOnDisk = file.delete()
        }

        // Also delete MediaStore row (handles scoped storage fallback + clears gallery cache).
        if (!contentUriStr.isNullOrBlank()) {
            runCatching {
                val rows = context.contentResolver.delete(Uri.parse(contentUriStr), null, null)
                if (rows > 0 && !file.exists()) {
                    deletedOnDisk = true
                }
            }
        }

        if (!deletedOnDisk && file.exists()) {
            deletedOnDisk = file.delete()
        }

        if (deletedOnDisk) {
            runCatching {
                MediaScannerConnection.scanFile(context, arrayOf(localPath), null, null)
            }
        }
        return deletedOnDisk && !file.exists()
    }
}
