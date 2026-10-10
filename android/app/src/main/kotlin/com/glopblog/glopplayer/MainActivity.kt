package com.glopblog.glopplayer

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val DELETE_CHANNEL = "com.glopblog.glopplayer/delete_song"
    private val DELETE_REQUEST_CODE = 1001
    private val CHANNEL = "glopplayer/media_scanner"
    private val EXTERNAL_AUDIO_CHANNEL = "glopplayer/external_audio"
    private val EXTERNAL_AUDIO_EVENTS = "glopplayer/external_audio/events"
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val pendingAudioIntents = mutableListOf<Intent>()
    private var audioEventSink: EventChannel.EventSink? = null
    private var initialAudioIntentHandled = false

    // Guarda o result do MethodChannel enquanto espera o usuário confirmar
    // no diálogo do sistema (fluxo assíncrono via onActivityResult).
    private var pendingDeleteResult: MethodChannel.Result? = null

    // Só usado no caminho do Android 10 (API 29): depois que o usuário
    // concede a permissão via RecoverableSecurityException, é preciso
    // tentar o delete de novo (o consentimento não apaga sozinho).
    private var pendingLegacyRetryUris: List<Uri>? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine) // deixa o audio_service registrar o dele primeiro

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAudio" -> result.success(takeInitialAudioUri())
                    "copyAudioToCache" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("INVALID_URI", "URI do áudio não informada", null)
                        } else {
                            ioExecutor.execute {
                                try {
                                    val path = copyAudioToCache(Uri.parse(uriString))
                                    runOnUiThread { result.success(path) }
                                } catch (e: Exception) {
                                    runOnUiThread {
                                        result.error(
                                            "AUDIO_COPY_FAILED",
                                            e.message ?: "Não foi possível ler o áudio compartilhado",
                                            null,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EXTERNAL_AUDIO_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                    val queuedIntents = pendingAudioIntents.toList()
                    pendingAudioIntents.clear()
                    queuedIntents.forEach { sendAudioIntent(it) }
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                }
            })

        // Channel para deletar músicas
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DELETE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deleteSongs" -> {
                        val ids = call.argument<List<Int>>("ids")
                        if (ids == null) {
                            result.error("INVALID_ARGS", "Lista de ids não informada", null)
                            return@setMethodCallHandler
                        }
                        deleteSongs(ids, result)
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel para scanear arquivos de mídia
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "scanFile") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            null,
                            null,
                        )
                        result.success(null)
                    } else {
                        result.error("NO_PATH", "Nenhum path informado", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!isAudioIntent(intent)) return
        initialAudioIntentHandled = true

        if (audioEventSink == null) {
            pendingAudioIntents.add(intent)
        } else {
            sendAudioIntent(intent)
        }
    }

    private fun takeInitialAudioUri(): String? {
        if (pendingAudioIntents.isNotEmpty()) {
            val pending = pendingAudioIntents.removeAt(0)
            return audioUriFromIntent(pending)?.toString()
        }

        if (initialAudioIntentHandled || !isAudioIntent(intent)) return null
        initialAudioIntentHandled = true
        return audioUriFromIntent(intent)?.toString()
    }

    private fun isAudioIntent(intent: Intent): Boolean {
        return intent.action == Intent.ACTION_VIEW ||
            intent.action == Intent.ACTION_SEND
    }

    private fun audioUriFromIntent(intent: Intent): Uri? {
        if (intent.action == Intent.ACTION_VIEW) return intent.data
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let { return it }
        } else {
            @Suppress("DEPRECATION")
            (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { return it }
        }
        return intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    }

    private fun sendAudioIntent(intent: Intent) {
        val uri = audioUriFromIntent(intent) ?: return
        audioEventSink?.success(uri.toString())
    }

    private fun copyAudioToCache(uri: Uri): String {
        if (uri.scheme == "file") {
            val source = File(uri.path ?: throw IOException("Caminho de arquivo inválido"))
            if (!source.isFile) throw IOException("O arquivo de áudio não existe")
            return source.absolutePath
        }
        if (uri.scheme != "content") {
            throw IOException("Esquema de URI não suportado: ${uri.scheme}")
        }

        val displayName = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))
            } else {
                null
            }
        } ?: uri.lastPathSegment ?: "audio"

        val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val extension = safeName.substringAfterLast('.', "")
            .takeIf { it.isNotBlank() && it.length <= 10 }
            ?: MimeTypeMap.getSingleton()
                .getExtensionFromMimeType(contentResolver.getType(uri))
                ?.takeIf { it.matches(Regex("[A-Za-z0-9]{1,10}")) }
            ?: "audio"
        val directory = File(cacheDir, "shared_audio")
        if (!directory.exists() && !directory.mkdirs()) {
            throw IOException("Não foi possível preparar o cache para o áudio")
        }
        val destination = File(directory, "${UUID.randomUUID()}.$extension")
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("Não foi possível abrir o áudio compartilhado")

        try {
            input.use { source ->
                destination.outputStream().use { target -> source.copyTo(target) }
            }
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
        return destination.absolutePath
    }

    private fun deleteSongs(ids: List<Int>, result: MethodChannel.Result) {
        val uris = ids.map { id ->
            ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                id.toLong()
            )
        }

        when {
            // Android 11+ (API 30+): pede confirmação em lote via diálogo do sistema.
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                try {
                    val pendingIntent = MediaStore.createDeleteRequest(contentResolver, uris)
                    pendingDeleteResult = result
                    pendingLegacyRetryUris = null
                    startIntentSenderForResult(
                        pendingIntent.intentSender,
                        DELETE_REQUEST_CODE,
                        null, 0, 0, 0
                    )
                } catch (e: Exception) {
                    result.error("DELETE_REQUEST_FAILED", e.message, null)
                }
            }

            // Android 10 (API 29): delete direto pode lançar RecoverableSecurityException.
            Build.VERSION.SDK_INT == Build.VERSION_CODES.Q -> {
                try {
                    val deletedCount = uris.sumOf { contentResolver.delete(it, null, null) }
                    result.success(deletedCount == uris.size)
                } catch (e: RecoverableSecurityException) {
                    try {
                        pendingDeleteResult = result
                        pendingLegacyRetryUris = uris
                        startIntentSenderForResult(
                            e.userAction.actionIntent.intentSender,
                            DELETE_REQUEST_CODE,
                            null, 0, 0, 0
                        )
                    } catch (sendEx: IntentSender.SendIntentException) {
                        result.error("DELETE_REQUEST_FAILED", sendEx.message, null)
                    }
                } catch (e: Exception) {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }

            // Android < 10 (API < 29): storage legado, delete direto sem diálogo.
            else -> {
                try {
                    val deletedCount = uris.sumOf { contentResolver.delete(it, null, null) }
                    result.success(deletedCount == uris.size)
                } catch (e: Exception) {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DELETE_REQUEST_CODE) return

        val userConfirmed = resultCode == Activity.RESULT_OK
        val retryUris = pendingLegacyRetryUris

        if (userConfirmed && retryUris != null) {
            // Caminho API 29: usuário concedeu, agora tenta apagar de novo.
            try {
                val deletedCount = retryUris.sumOf { contentResolver.delete(it, null, null) }
                pendingDeleteResult?.success(deletedCount == retryUris.size)
            } catch (e: Exception) {
                pendingDeleteResult?.error("DELETE_FAILED", e.message, null)
            }
        } else {
            // Caminho API 30+: o próprio sistema já executou (ou o usuário cancelou).
            pendingDeleteResult?.success(userConfirmed)
        }

        pendingDeleteResult = null
        pendingLegacyRetryUris = null
    }
}