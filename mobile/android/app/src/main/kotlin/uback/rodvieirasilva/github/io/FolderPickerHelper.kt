package uback.rodvieirasilva.github.io

import android.net.Uri
import android.provider.DocumentsContract

sealed class FolderPickOutcome {
    data class Selected(val relativePath: String) : FolderPickOutcome()
    data class Error(val message: String) : FolderPickOutcome()
}

/**
 * Resolves Android Storage Access Framework (ACTION_OPEN_DOCUMENT_TREE) tree URIs
 * into clean relative paths under internal storage (e.g. `DJI/Media`, `Documents/Scans`).
 */
object FolderPickerHelper {

    fun resolveTreeUri(uri: Uri): FolderPickOutcome {
        val docId = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull()
            ?: return FolderPickOutcome.Error(
                "Could not read selected folder. Please pick a folder from internal storage.",
            )
        return resolveDocumentId(docId)
    }

    fun resolveDocumentId(docId: String): FolderPickOutcome {
        val decoded = Uri.decode(docId).replace('\\', '/').trim()
        val colonIdx = decoded.indexOf(':')
        if (colonIdx <= 0) {
            return FolderPickOutcome.Error(
                "Select a folder on internal storage (cloud or virtual folders are not supported).",
            )
        }

        val volume = decoded.substring(0, colonIdx).lowercase()
        val rawPath = decoded.substring(colonIdx + 1).trim('/')

        return when (volume) {
            "primary" -> {
                if (rawPath.isEmpty()) {
                    FolderPickOutcome.Error(
                        "Please select a specific subfolder instead of the root of internal storage.",
                    )
                } else {
                    FolderPickOutcome.Selected(rawPath)
                }
            }

            "home" -> {
                val rel = if (rawPath.isEmpty()) "Documents" else "Documents/$rawPath"
                FolderPickOutcome.Selected(rel)
            }

            else -> FolderPickOutcome.Error(
                "Please choose a folder on internal storage (external SD or cloud storage is not supported yet).",
            )
        }
    }
}
