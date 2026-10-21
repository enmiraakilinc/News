package com.melek.stargaleri

import android.app.*
import android.content.*
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/** Device-local sounds, independent from microphone capture and conversation audio. */
object CallRingtone {
    private const val SYSTEM = 7201
    private const val FILE = 7202
    private var pending: MethodChannel.Result? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var ringingId: String? = null
    private fun prefs(c: Context) = c.getSharedPreferences("call_ringtone", Context.MODE_PRIVATE)
    private fun mode(c: Context) = prefs(c).getString("mode", "sound") ?: "sound"
    private fun uri(c: Context): Uri = prefs(c).getString("uri", null)?.let(Uri::parse)
        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    fun settings(c: Context): Map<String, String> = mapOf("mode" to mode(c),
        "name" to (prefs(c).getString("name", null) ?: "Telefonun varsayılan zil sesi"))

    fun channel(c: Context): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest((mode(c) + ":" + uri(c)).toByteArray()).take(8).joinToString("") { "%02x".format(it) }
        val id = "incoming_calls_v2_$digest"
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val old = prefs(c).getString("channel", null)?.let { manager.getNotificationChannel(it) }
            // Keep an explicit Android channel block/importance when changing the tone.
            val n = NotificationChannel(id, "Gelen aramalar", old?.importance ?: NotificationManager.IMPORTANCE_HIGH)
            n.lockscreenVisibility = Notification.VISIBILITY_SECRET
            n.setShowBadge(false)
            n.enableVibration(mode(c) != "silent")
            n.vibrationPattern = if (mode(c) != "silent") longArrayOf(0, 400, 600, 400) else longArrayOf(0)
            n.setSound(if (mode(c) == "sound") uri(c) else null,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
            manager.createNotificationChannel(n)
            prefs(c).edit().putString("channel", id).apply()
        }
        return id
    }
    fun legacySound(c: Context, builder: Notification.Builder) {
        if (Build.VERSION.SDK_INT >= 26) return
        builder.setSound(if (mode(c) == "sound") uri(c) else null)
        if (mode(c) != "silent") builder.setVibrate(longArrayOf(0, 400, 600, 400))
    }
    fun blocked(c: Context): Boolean {
        val n = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!n.areNotificationsEnabled()) return true
        return Build.VERSION.SDK_INT >= 26 && (
            n.getNotificationChannel("incoming_calls")?.importance == NotificationManager.IMPORTANCE_NONE ||
            n.getNotificationChannel(channel(c))?.importance == NotificationManager.IMPORTANCE_NONE)
    }
    fun stop(id: String? = null) {
        if (id != null && id != ringingId) return
        handler.removeCallbacksAndMessages(null)
        try { ringtone?.stop() } catch (_: Exception) {}
        try { vibrator?.cancel() } catch (_: Exception) {}
        ringtone = null; vibrator = null; ringingId = null
    }
    fun ring(c: Context, id: String, preview: Boolean = false) {
        if (ringingId == id) return
        stop()
        if (mode(c) == "silent" || blocked(c)) return
        val audio = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notifications = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT ||
            notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) return
        ringingId = id
        val currentChannel = if (Build.VERSION.SDK_INT >= 26) notifications.getNotificationChannel(channel(c)) else null
        val selectedUri = if (Build.VERSION.SDK_INT >= 26) currentChannel?.sound else uri(c)
        if (mode(c) == "sound" && selectedUri != null && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                ringtone = RingtoneManager.getRingtone(c, selectedUri)
                    ?: RingtoneManager.getRingtone(c, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build()
                if (Build.VERSION.SDK_INT >= 28) ringtone?.isLooping = true
                ringtone?.play()
            } catch (_: Exception) {
                try {
                    ringtone = RingtoneManager.getRingtone(c, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                    ringtone?.play()
                } catch (_: Exception) {}
            }
        }
        if (currentChannel == null || currentChannel.shouldVibrate()) try {
            @Suppress("DEPRECATION")
            val v = c.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            vibrator = v
            if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 700), 0),
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build())
            else @Suppress("DEPRECATION") v.vibrate(longArrayOf(0, 400, 700), 0)
        } catch (_: Exception) {}
        handler.postDelayed({ stop(id) }, if (preview) 5000 else 45000)
    }
    fun attach(activity: FlutterActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/call_ringtone").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "get" -> result.success(settings(activity))
                    "setMode" -> {
                        val value = call.argument<String>("mode")
                        require(value in listOf("sound", "vibrate", "silent"))
                        stop(); prefs(activity).edit().putString("mode", value).apply()
                        channel(activity); result.success(settings(activity))
                    }
                    "default" -> {
                        stop(); prefs(activity).edit().remove("uri").remove("name").apply()
                        channel(activity); result.success(settings(activity))
                    }
                    "pickSystem", "pickFile" -> {
                        if (pending != null) { result.error("busy", "Önce açık ses seçimini tamamla.", null); return@setMethodCallHandler }
                        val system = call.method == "pickSystem"
                        val intent = if (system) Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_RINGTONE)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            .putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, uri(activity))
                        else Intent(Intent.ACTION_OPEN_DOCUMENT).setType("audio/*").addCategory(Intent.CATEGORY_OPENABLE)
                            .putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        stop()
                        pending = result
                        @Suppress("DEPRECATION")
                        activity.startActivityForResult(intent, if (system) SYSTEM else FILE)
                    }
                    "preview" -> { ring(activity, "preview", true); result.success(null) }
                    "ring" -> {
                        val id = call.argument<String>("id") ?: ""
                        require(Regex("^[A-Za-z0-9]{20}$").matches(id))
                        ring(activity, id); result.success(null)
                    }
                    "stop" -> { stop(call.argument<String>("id")); result.success(null) }
                    "channelSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, channel(activity)))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                pending = null
                result.error("sound_failed", "Ses ayarı değiştirilemedi. Telefon ayarlarını veya ses dosyasını kontrol et.", null)
            }
        }
    }
    @Suppress("DEPRECATION")
    fun activityResult(c: Context, request: Int, code: Int, data: Intent?): Boolean {
        if (request != SYSTEM && request != FILE) return false
        val result = pending ?: return true
        pending = null
        if (code != Activity.RESULT_OK) { result.success(settings(c)); return true }
        try {
            val picked: Uri? = if (request == SYSTEM) data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI) else data?.data
            require(picked != null && picked.scheme == "content")
            if (request == FILE) {
                c.contentResolver.takePersistableUriPermission(picked, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                c.contentResolver.openAssetFileDescriptor(picked, "r")?.use {
                    require(it.length < 0 || it.length <= 10L * 1024 * 1024)
                } ?: throw IllegalArgumentException()
            }
            val name = if (request == SYSTEM) RingtoneManager.getRingtone(c, picked)?.getTitle(c) else "Seçtiğin ses dosyası"
            stop()
            prefs(c).edit().putString("uri", picked.toString()).putString("name", name ?: "Zil sesi").apply()
            channel(c)
            result.success(settings(c))
        } catch (_: Exception) {
            result.error("file_failed", "Ses seçilemedi. Cihazına indirdiğin, en fazla 10 MB ses dosyasını seç.", null)
        }
        return true
    }
    fun detach() {
        stop()
        pending?.error("cancelled", "Ses seçimi kapatıldı.", null); pending = null
    }
}
