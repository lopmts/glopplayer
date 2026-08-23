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
import androidx.annotation.NonNull
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val DELETE_CHANNEL = "com.glopblog.glopplayer/delete_song"
    private val DELETE_REQUEST_CODE = 1001
    private val CHANNEL = "glopplayer/media_scanner"
    // Guarda o result do MethodChannel enquanto espera o usuário confirmar
    // no diálogo do sistema (fluxo assíncrono via onActivityResult).
    private var pendingDeleteResult: MethodChannel.Result? = null

    // Só usado no caminho do Android 10 (API 29): depois que o usuário
    // concede a permissão via RecoverableSecurityException, é preciso
    // tentar o delete de novo (o consentimento não apaga sozinho).
    private var pendingLegacyRetryUris: List<Uri>? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine) // deixa o audio_service registrar o dele primeiro

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