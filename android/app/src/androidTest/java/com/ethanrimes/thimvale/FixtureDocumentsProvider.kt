package com.ethanrimes.thimvale

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsProvider
import java.io.File

/** Test APK only. Exposes only its own disposable fixture directory, never app/user folders. */
class FixtureDocumentsProvider : DocumentsProvider() {
    private val root
        get() = File(requireNotNull(context).cacheDir, "saf-fixtures").apply { mkdirs() }

    private fun file(id: String): File {
        val result = if (id == "root") root else File(root, id.removePrefix("root/"))
        require(
            result.canonicalPath == root.canonicalPath ||
                result.canonicalPath.startsWith(root.canonicalPath + "/")
        )
        return result
    }

    private fun id(file: File) = if (file == root) "root" else "root/" + file.relativeTo(root).path

    private val columns =
        arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
        )

    private fun row(cursor: MatrixCursor, document: File) {
        cursor.newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, id(document))
            add(Document.COLUMN_DISPLAY_NAME, document.name)
            add(
                Document.COLUMN_MIME_TYPE,
                if (document.isDirectory) Document.MIME_TYPE_DIR else "text/plain",
            )
            add(
                Document.COLUMN_FLAGS,
                if (document.isDirectory) Document.FLAG_DIR_SUPPORTS_CREATE
                else Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE,
            )
            add(Document.COLUMN_SIZE, document.length())
            add(Document.COLUMN_LAST_MODIFIED, document.lastModified())
        }
    }

    override fun onCreate() = true

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(arrayOf("root_id", "document_id", "title", "flags"))

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        MatrixCursor(columns).also { row(it, file(documentId)) }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor =
        MatrixCursor(columns).also { cursor ->
            file(parentDocumentId).listFiles().orEmpty().forEach { row(cursor, it) }
        }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor =
        ParcelFileDescriptor.open(file(documentId), ParcelFileDescriptor.parseMode(mode))

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String,
    ): String {
        require(displayName.isNotBlank() && displayName != "." && displayName != ".." && !displayName.contains('/') && !displayName.contains('\\'))
        val target = File(file(parentDocumentId), displayName)
        check(if (mimeType == Document.MIME_TYPE_DIR) target.mkdir() else target.createNewFile())
        return id(target)
    }

    override fun deleteDocument(documentId: String) {
        require(documentId != "root")
        check(file(documentId).delete())
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String) =
        file(documentId).canonicalPath.startsWith(file(parentDocumentId).canonicalPath + "/")
}
