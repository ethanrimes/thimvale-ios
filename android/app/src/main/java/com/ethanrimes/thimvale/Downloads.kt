package com.ethanrimes.thimvale

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.work.*
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

data class DownloadStatus(val id: Long, val title: String, val progress: Float, val state: String)

class Downloads(private val library: Library) {
    private val manager = library.context.getSystemService(DownloadManager::class.java)
    private val jobs = LocalState(library.context, "downloads.json")

    fun enqueue(file: RemoteFile): Long {
        require(file.bytes > 4 && Regex("[a-fA-F0-9]{64}").matches(file.sha256)) {
            "A verified size and SHA-256 checksum are required."
        }
        require(Uri.parse(file.url).scheme == "https") { "Downloads require HTTPS." }
        val target = library.file(file.name)
        require(!target.exists()) { "This edition is already installed." }
        require(library.directory.usableSpace > file.bytes + 256L * 1024 * 1024) {
            "Not enough free storage for this download."
        }
        val existing = jobs.read()
        require(
            existing.keys().asSequence().none {
                existing.getJSONObject(it).optString("name") == file.name
            }
        ) {
            "This download is already queued."
        }
        val pending = File(library.directory, ".${file.name}.pending")
        require(!pending.exists()) {
            "An unfinished download exists. Remove it from Downloads before retrying."
        }
        val request =
            DownloadManager.Request(Uri.parse(file.url))
                .setTitle(file.title)
                .setDescription("Thimvale · ${file.license}")
                .setDestinationUri(Uri.fromFile(pending))
                .setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                )
                .setAllowedOverMetered(library.state.read().optBoolean("cellular", false))
                .setAllowedOverRoaming(false)
        val id = manager.enqueue(request)
        jobs.change { it.put(id.toString(), file.json()) }
        schedule(library.context, id)
        return id
    }

    fun statuses(): List<DownloadStatus> {
        val json = jobs.read()
        return json
            .keys()
            .asSequence()
            .mapNotNull { key ->
                manager.query(DownloadManager.Query().setFilterById(key.toLong())).use { c ->
                    if (!c.moveToFirst())
                        return@mapNotNull DownloadStatus(
                            key.toLong(),
                            json.getJSONObject(key).getString("title"),
                            0f,
                            "Download removed; cancel to clear",
                        )
                    val downloaded =
                        c.getLong(
                            c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        )
                    val size =
                        c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    val status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    DownloadStatus(
                        key.toLong(),
                        json.getJSONObject(key).getString("title"),
                        if (size > 0) downloaded.toFloat() / size else 0f,
                        when (status) {
                            DownloadManager.STATUS_SUCCESSFUL ->
                                json.getJSONObject(key).optString("error", "Verifying")
                            DownloadManager.STATUS_FAILED -> "Download failed; cancel and retry"
                            DownloadManager.STATUS_PAUSED -> "Waiting for network or storage"
                            else -> "Downloading"
                        },
                    )
                }
            }
            .toList()
    }

    fun cancel(id: Long) {
        val data = jobs.read().optJSONObject(id.toString()) ?: return
        WorkManager.getInstance(library.context).cancelUniqueWork("verify-$id")
        manager.remove(id)
        val target = library.file(data.getString("name"))
        File(target.parentFile, ".${target.name}.pending").delete()
        jobs.change { it.remove(id.toString()) }
    }

    fun verify(id: Long): Boolean {
        val data = jobs.read().optJSONObject(id.toString()) ?: return true
        manager.query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (!c.moveToFirst()) return true
            if (
                c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) !=
                    DownloadManager.STATUS_SUCCESSFUL
            )
                return false
        }
        val remote = RemoteFile.from(data)
        val target = library.file(remote.name)
        val pending = File(target.parentFile, ".${target.name}.pending")
        try {
            check(!target.exists()) { "This file is already installed." }
            check(pending.length() == remote.bytes) {
                "Size verification failed. Cancel and retry."
            }
            val digest = MessageDigest.getInstance("SHA-256")
            pending.inputStream().buffered().use { input ->
                val buffer = ByteArray(128 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    digest.update(buffer, 0, n)
                }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            check(actual.equals(remote.sha256, true)) {
                "Checksum verification failed. Cancel and retry."
            }
            validateHeader(pending, target.extension)
            // Recheck cancellation before publishing. renameTo never targets another user's file.
            if (!jobs.read().has(id.toString())) return true
            check(!target.exists() && pending.renameTo(target)) {
                "Could not finish installing this download."
            }
            jobs.change { it.remove(id.toString()) }
            return true
        } catch (e: Exception) {
            jobs.change {
                it.optJSONObject(id.toString())?.put("error", e.message ?: "Verification failed")
            }
            return true // Require explicit retry; do not loop on a corrupt multi-GB file.
        }
    }

    companion object {
        fun validateHeader(file: File, extension: String) {
            val magic = file.inputStream().use { it.readBounded(4) }
            val expected =
                if (extension == "gguf") byteArrayOf(0x47, 0x47, 0x55, 0x46)
                else if (extension == "zim") byteArrayOf(0x5a, 0x49, 0x4d, 0x04)
                else error("Unsupported file type.")
            require(magic.contentEquals(expected)) {
                "The file is not a valid ${extension.uppercase()} archive."
            }
        }

        fun schedule(context: Context, id: Long) {
            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    "verify-$id",
                    ExistingWorkPolicy.KEEP,
                    OneTimeWorkRequestBuilder<VerifyDownload>()
                        .setInputData(workDataOf("download" to id))
                        .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.SECONDS)
                        .build(),
                )
        }
    }
}

class VerifyDownload(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result =
        if (
            Downloads((applicationContext as ThimvaleApplication).library)
                .verify(inputData.getLong("download", -1))
        )
            Result.success()
        else Result.retry()
}

class DownloadFinished : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            if (LocalState(context, "downloads.json").read().has(id.toString()))
                Downloads.schedule(context, id)
        }
    }
}
