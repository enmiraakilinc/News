package com.melek.stargaleri

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.UUID
import kotlin.math.ceil

/** Sequential exports keep memory bounded; every completed MP4 is size-checked. */
@UnstableApi
class VideoParts(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var result: MethodChannel.Result? = null
    private var transformer: Transformer? = null
    private val pending = ArrayDeque<Pair<Long, Long>>()
    private val outputs = mutableListOf<File>()
    private val files = mutableListOf<File>()
    private var source: File? = null
    private var limit = 100L * 1024 * 1024
    private val timeout = Runnable { fail("Video hazırlama süresi aşıldı. Yeniden dene.") }

    fun split(path: String?, maxBytes: Long, reply: MethodChannel.Result) {
        if (result != null) { reply.error("busy", "Video hazırlanıyor.", null); return }
        val input = path?.let { File(it) }
        if (input == null || !input.isFile || maxBytes != 100L * 1024 * 1024) {
            reply.error("invalid", "Video bulunamadı.", null); return
        }
        result = reply
        source = input
        limit = maxBytes
        handler.postDelayed(timeout, 10 * 60 * 1000L)
        Thread {
            val metadata = MediaMetadataRetriever()
            try {
                metadata.setDataSource(input.absolutePath)
                val duration = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                    ?: throw IllegalArgumentException()
                require(duration > 0)
                handler.post {
                    if (result !== reply) return@post
                    val count = ceil(input.length().toDouble() / limit).toInt().coerceAtLeast(2)
                    for (i in 0 until count) {
                        val start = duration * i / count
                        val end = duration * (i + 1) / count
                        if (end > start) pending.add(start to end)
                    }
                    next()
                }
            } catch (_: Exception) {
                handler.post { if (result === reply) fail("Video okunamadı.") }
            } finally { metadata.release() }
        }.start()
    }

    private fun next() {
        if (result == null) return
        if (pending.isEmpty()) {
            val reply = result
            result = null
            handler.removeCallbacks(timeout)
            reply?.success(outputs.map { it.absolutePath })
            outputs.clear(); files.clear(); source = null
            return
        }
        val range = pending.removeFirst()
        val out = File(context.cacheDir, "neural_media_part_${UUID.randomUUID()}.mp4")
        files.add(out)
        val item = MediaItem.Builder().setUri(Uri.fromFile(source!!))
            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(range.first).setEndPositionMs(range.second).build()).build()
        val export = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    transformer = null
                    if (result == null) { out.delete(); return }
                    if (out.length() in 1..limit) outputs.add(out)
                    else {
                        out.delete()
                        val middle = (range.first + range.second) / 2
                        if (range.second - range.first < 200 || outputs.size + pending.size > 1000) {
                            fail("Video parçalara ayrılamadı."); return
                        }
                        pending.addFirst(middle to range.second)
                        pending.addFirst(range.first to middle)
                    }
                    handler.post { next() }
                }
                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    transformer = null
                    fail("Video hazırlanamadı. Başka bir kayıt deneyebilirsin.")
                }
            }).build()
        transformer = export
        try { export.start(item, out.absolutePath) }
        catch (_: Exception) { fail("Video hazırlanamadı.") }
    }

    private fun fail(message: String) {
        val reply = result
        result = null
        handler.removeCallbacks(timeout)
        transformer?.cancel(); transformer = null
        files.forEach { it.delete() }
        files.clear(); outputs.clear(); pending.clear(); source = null
        reply?.error("video", message, null)
    }
    fun close() { fail("Video hazırlama iptal edildi.") }
}
