package com.melek.stargaleri

import android.Manifest
import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.*
import android.os.*
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine

/** Explicit user-started microphone sessions. No file/network I/O in hold mode. */
object MicrophoneSessionBridge {
    var channel: MethodChannel? = null
    var pending: MethodChannel.Result? = null
    const val CHANNEL = "microphone_session"
    fun prepare(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL, "Mikrofon oturumları", NotificationManager.IMPORTANCE_LOW)
            ch.setSound(null, null); ch.enableVibration(false)
            ch.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            if (Build.VERSION.SDK_INT >= 33) ch.setBlockable(true)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }
    fun drawerHidden(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        return !NotificationManagerCompat.from(context).areNotificationsEnabled() ||
            context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance == NotificationManager.IMPORTANCE_NONE
    }
    fun attach(activity: MainActivity, engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app/microphone_session").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        prepare(activity)
                        result.success(mapOf("drawerHidden" to drawerHidden(activity), "supported" to (Build.VERSION.SDK_INT >= 33)))
                    }
                    "settings" -> {
                        prepare(activity)
                        val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName).putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + activity.packageName))
                        activity.startActivity(intent); result.success(null)
                    }
                    "requestStop" -> {
                        if (MicrophoneSessionService.mode != null) activity.startService(Intent(activity, MicrophoneSessionService::class.java).setAction("stop"))
                        result.success(null)
                    }
                    "status" -> result.success(mapOf(
                        "mode" to MicrophoneSessionService.mode,
                        "silenced" to MicrophoneSessionService.silenced()))
                    "start" -> {
                        val mode = call.argument<String>("mode")
                        if (mode !in listOf("hold", "voice")) {
                            result.error("invalid", "Geçersiz mikrofon oturumu.", null)
                        } else if (Build.VERSION.SDK_INT >= 33 && !drawerHidden(activity)) {
                            result.error("notification_visible", "Önce Mikrofon oturumları bildirim kanalını telefon ayarlarından kapat.", null)
                        } else if (!activity.microphoneStartAllowed) {
                            result.error("foreground_required", "Önce uygulamayı açıp yeniden başlat.", null)
                        } else if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                            result.error("permission_denied", "Mikrofon izni gerekli.", null)
                        } else if (!activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                                .getBoolean("flutter.feature_access_microphone", true)) {
                            result.error("disabled", "Mikrofon kullanımı ayarlardan kapalı.", null)
                        } else if (pending != null || MicrophoneSessionService.mode != null || VoiceOngoingService.activeId != null) {
                            result.error("microphone_busy", "Önce açık mikrofon oturumunu veya aramayı durdur.", null)
                        } else {
                            pending = result
                            try {
                                val intent = Intent(activity, MicrophoneSessionService::class.java).putExtra("mode", mode)
                                if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                            } catch (_: Exception) {
                                pending = null
                                result.error("start_failed", "Mikrofon oturumu başlatılamadı. Uygulamayı açık tutup yeniden dene.", null)
                            }
                        }
                    }
                    "stop" -> {
                        // A stale voice callback must never stop a later hold session.
                        val expected = call.argument<String>("mode")
                        if (expected == MicrophoneSessionService.mode) {
                            activity.stopService(Intent(activity, MicrophoneSessionService::class.java))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    fun ready() { pending?.success(null); pending = null }
    fun failed() {
        pending?.error("start_failed", "Mikrofona erişilemedi. Başka bir kayıt veya arama varsa kapatıp yeniden dene.", null)
        pending = null
    }
}

class MicrophoneSessionService : Service() {
    companion object {
        @Volatile var mode: String? = null; private set
        @Volatile private var capture: AudioRecord? = null
        fun silenced(): Boolean = if (Build.VERSION.SDK_INT >= 29) {
            capture?.activeRecordingConfiguration?.isClientSilenced ?: false
        } else false
    }
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    private var worker: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?) = null

    @SuppressLint("MissingPermission", "WakelockTimeout")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            if (mode == "voice" && MicrophoneSessionBridge.channel != null) {
                // Stop in the recorder owner, retaining the draft for preview.
                MicrophoneSessionBridge.channel?.invokeMethod("stopRequested", null)
            } else stopSelf()
            return START_NOT_STICKY
        }
        if (mode != null) return START_NOT_STICKY
        val requested = intent?.getStringExtra("mode")
        if (requested !in listOf("hold", "voice")) { stopSelf(); return START_NOT_STICKY }
        try {
            MicrophoneSessionBridge.prepare(this)
            val channelId = MicrophoneSessionBridge.CHANNEL
            val stop = PendingIntent.getService(this, 1841, Intent(this, MicrophoneSessionService::class.java).setAction("stop"),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(this, 1842, Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle(if (requested == "hold") "Mikrofon oturumu açık" else "Ses kaydı oturumu açık")
                .setContentText("Ekran kilitliyken devam eder. Durdurmak için düğmeye bas.")
                .setContentIntent(open).setOngoing(true).setSilent(true)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .addAction(android.R.drawable.ic_media_pause, "Durdur", stop).build()
            if (Build.VERSION.SDK_INT >= 30) startForeground(1840, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else startForeground(1840, notification)
            mode = requested
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Neural:MicrophoneSession").apply { acquire() }
            if (requested == "hold") {
                val format = AudioFormat.Builder().setSampleRate(16000)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build()
                val builder = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.MIC)
                    .setAudioFormat(format).setBufferSizeInBytes(maxOf(4096,
                        AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)))
                if (Build.VERSION.SDK_INT >= 30) builder.setPrivacySensitive(true)
                capture = builder.build()
                check(capture?.state == AudioRecord.STATE_INITIALIZED)
                capture!!.startRecording()
                check(capture?.recordingState == AudioRecord.RECORDSTATE_RECORDING)
                running = true
                worker = Thread({
                    Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                    val buffer = ByteArray(2048)
                    try {
                        while (running) {
                            val count = capture?.read(buffer, 0, buffer.size) ?: break
                            if (count < 0) throw IllegalStateException("capture stopped")
                            // Consume and discard immediately. Never persist or transmit audio.
                            buffer.fill(0)
                        }
                    } catch (_: Exception) { if (running) main.post { stopSelf() } }
                    finally { buffer.fill(0) }
                }, "microphone-discard").apply { start() }
            }
            MicrophoneSessionBridge.ready()
        } catch (_: Exception) {
            MicrophoneSessionBridge.failed()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (mode == "voice") MicrophoneSessionBridge.channel?.invokeMethod("stopRequested", null)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
    override fun onDestroy() {
        running = false
        try { capture?.stop() } catch (_: Exception) {}
        try { worker?.join(1000) } catch (_: Exception) {}
        capture?.release(); capture = null; worker = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        mode = null
        MicrophoneSessionBridge.failed()
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else { @Suppress("DEPRECATION") stopForeground(true) }
        super.onDestroy()
    }
}
