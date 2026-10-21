package com.melek.stargaleri

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

object AudioFilesBridge {
    fun attach(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/audio_files")
            .setMethodCallHandler { call, result ->
                if (call.method != "openWith") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    val file = File(call.argument<String>("path") ?: "").canonicalFile
                    val roots = listOf(activity.cacheDir, activity.filesDir).map { it.canonicalFile }
                    val types = mapOf("m4a" to "audio/mp4", "aac" to "audio/aac",
                        "mp3" to "audio/mpeg", "wav" to "audio/wav", "ogg" to "audio/ogg",
                        "opus" to "audio/ogg", "flac" to "audio/flac", "amr" to "audio/amr", "3ga" to "audio/3gpp")
                    val mime = types[file.extension.lowercase()]
                    require(file.isFile && file.length() <= 20L * 1024 * 1024 && mime != null &&
                        roots.any { file.path.startsWith(it.path + File.separator) })
                    val uri = FileProvider.getUriForFile(activity,
                        activity.packageName + ".fileProvider.com.crazecoder.openfile", file)
                    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    view.clipData = ClipData.newRawUri("Ses kaydı", uri)
                    if (view.resolveActivity(activity.packageManager) == null) {
                        result.error("no_app", "Bu ses biçimini açabilen bir uygulama bulunamadı.", null)
                    } else {
                        activity.startActivity(Intent.createChooser(view, "Birlikte aç"))
                        result.success(null)
                    }
                } catch (_: Exception) {
                    result.error("unavailable", "Ses dosyası açılamadı. Dosyayı yeniden yükleyip dene.", null)
                }
            }
    }
}
