package com.ethanrimes.thimvale

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

class LocalState(context: Context, name: String = "state.json") {
    companion object {
        private val lock = Any()
    }

    private val file = AtomicFile(File(context.filesDir, name))

    fun read(): JSONObject =
        synchronized(lock) {
            try {
                JSONObject(file.openRead().bufferedReader().use { it.readText() })
            } catch (_: java.io.FileNotFoundException) {
                JSONObject()
            }
        }

    fun change(block: (JSONObject) -> Unit) =
        synchronized(lock) {
            val json = read().also(block)
            val out = file.startWrite()
            try {
                out.write(json.toString().toByteArray())
                file.finishWrite(out)
            } catch (e: Exception) {
                file.failWrite(out)
                throw e
            }
        }
}

fun java.io.InputStream.readBounded(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(minOf(limit, 8192))
    while (output.size() < limit) {
        val count = read(buffer, 0, minOf(buffer.size, limit - output.size()))
        if (count < 0) break
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}

class Secrets(context: Context) {
    private val prefs = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)
    private val key: SecretKey
        get() {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            return (store.getKey("thimvale-secrets", null) as? SecretKey)
                ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    .apply {
                        init(
                            KeyGenParameterSpec.Builder(
                                    "thimvale-secrets",
                                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                                )
                                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                                .build()
                        )
                    }
                    .generateKey()
        }

    fun get(name: String): String {
        val data = prefs.getString(name, null) ?: return ""
        val parts = data.split(":")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)),
        )
        return cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }

    fun set(name: String, value: String) {
        if (value.isBlank()) {
            prefs.edit().remove(name).apply()
            return
        }
        val cipher =
            Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key) }
        val encode = { bytes: ByteArray -> Base64.encodeToString(bytes, Base64.NO_WRAP) }
        prefs
            .edit()
            .putString(name, encode(cipher.iv) + ":" + encode(cipher.doFinal(value.toByteArray())))
            .apply()
    }
}

class Library(val context: Context) {
    val state = LocalState(context)
    val secrets = Secrets(context)
    val directory: File =
        (context.getExternalFilesDir("library") ?: File(context.filesDir, "library")).apply {
            mkdirs()
        }

    fun files(extension: String): List<File> =
        directory
            .listFiles()
            ?.filter { it.isFile && it.extension == extension }
            ?.sortedBy { it.name }
            .orEmpty()

    fun file(name: String): File {
        require(name.isNotBlank() && name == File(name).name && !name.startsWith(".")) {
            "Invalid library filename."
        }
        return File(directory, name)
    }

    val models: List<Model> by lazy {
        JSONArray(context.assets.open("models.json").bufferedReader().use { it.readText() })
            .objects()
            .map(Model::from)
    }

    fun permission(capability: Capability): Permission =
        state.read().optJSONObject("permissions")?.optString(capability.name)?.let {
            runCatching { Permission.valueOf(it) }.getOrNull()
        } ?: Permission.ASK

    fun setPermission(capability: Capability, permission: Permission) =
        state.change { j ->
            j.put(
                "permissions",
                (j.optJSONObject("permissions") ?: JSONObject()).put(
                    capability.name,
                    permission.name,
                ),
            )
        }
}
