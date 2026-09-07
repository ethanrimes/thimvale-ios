package com.ethanrimes.thimvale

import android.app.ActivityManager
import android.content.Context
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray

class NativeEngine(context: Context) {
    companion object {
        init {
            System.loadLibrary("thimvale")
        }
    }

    fun interface TokenCallback {
        fun onBytes(bytes: ByteArray)
    }

    private external fun create(): Long

    private external fun load(handle: Long, path: ByteArray)

    private external fun generate(
        handle: Long,
        messages: ByteArray,
        maxTokens: Int,
        callback: TokenCallback,
    ): ByteArray

    private external fun unload(handle: Long)

    private external fun reset(handle: Long)

    private external fun cancel(handle: Long)

    private val handle = create()
    private val mutex = Mutex()
    private val activity = context.getSystemService(ActivityManager::class.java)
    @Volatile
    var loadedPath: String? = null
        private set

    fun stop() = cancel(handle)

    suspend fun release() {
        stop()
        withContext(Dispatchers.IO) {
            mutex.withLock {
                unload(handle)
                loadedPath = null
            }
        }
    }

    private fun ensureLoaded(file: File) {
        if (loadedPath == file.absolutePath) return
        val memory = ActivityManager.MemoryInfo().also(activity::getMemoryInfo)
        require(file.length() + 384L * 1024 * 1024 < memory.availMem) {
            "Not enough available memory. Choose a smaller quantization."
        }
        loadedPath = null
        load(handle, file.absolutePath.toByteArray())
        loadedPath = file.absolutePath
    }

    suspend fun select(file: File) =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                reset(handle)
                ensureLoaded(file)
            }
        }

    suspend fun answer(
        file: File,
        messages: JSONArray,
        maxTokens: Int = 700,
        onToken: (String) -> Unit,
    ): String =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureActive()
                reset(handle)
                ensureLoaded(file)
                ensureActive()
                generate(handle, messages.toString().toByteArray(), maxTokens) { data ->
                        // Decode accumulated bytes so a token boundary never corrupts a split UTF-8
                        // character.
                        val decoder = Charsets.UTF_8.newDecoder()
                        val chars = java.nio.CharBuffer.allocate(data.size)
                        decoder.decode(java.nio.ByteBuffer.wrap(data), chars, false)
                        chars.flip()
                        onToken(chars.toString())
                    }
                    .toString(Charsets.UTF_8)
            }
        }
}
