package com.melek.stargaleri

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/** Protected FCM receiver. Consent is rechecked online on the receiving phone. */
class WakeMessageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("type") != "wake") return
        if (!context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.alarm_notifications_enabled", true)) return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        if (intent.getStringExtra("recipientUid") != uid) return
        val source = intent.getStringExtra("sourceKey") ?: return
        val sender = intent.getStringExtra("senderUid") ?: return
        val sent = intent.getStringExtra("sentAt")?.toLongOrNull() ?: return
        val eventId = intent.getStringExtra("eventId") ?: return
        if (!Regex("^[a-fA-F0-9-]{36}$").matches(eventId)) return
        if (System.currentTimeMillis() - sent !in 0..90000) return
        if (!Regex("^(chat|couple)/[A-Za-z0-9_-]{1,200}$").matches(source)) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel("wakeup_alarm")?.importance == NotificationManager.IMPORTANCE_NONE) return
        val device = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.wakeup_device_id", null) ?: return
        val hash = MessageDigest.getInstance("SHA-256").digest("$source/$device".toByteArray())
            .joinToString("") { "%02x".format(it) }
        if (context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.wakeup_disabled_${uid}_${hash}", false)) return
        val pending = goAsync()
        val finished = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        val timeout = Runnable { if (finished.compareAndSet(false, true)) pending.finish() }
        handler.postDelayed(timeout, 8000)
        val db = FirebaseFirestore.getInstance()
        db.document("chatAccounts/$uid/wakePermissions/$hash").get(Source.SERVER).addOnCompleteListener { consent ->
            if (finished.get()) return@addOnCompleteListener
            val settings = if (consent.isSuccessful) consent.result?.data else null
            if (!consent.isSuccessful || settings?.get("enabled") != true || settings?.get("sourceKey") != source || settings?.get("deviceId") != device) {
                if (finished.compareAndSet(false, true)) { handler.removeCallbacks(timeout); pending.finish() }
                return@addOnCompleteListener
            }
            val parts = source.split('/')
            db.document("${if (parts[0] == "chat") "chats" else "couples"}/${parts[1]}").get(Source.SERVER).addOnCompleteListener chatResult@ { chat ->
                if (!finished.compareAndSet(false, true)) return@chatResult
                handler.removeCallbacks(timeout)
                try {
                    val members = if (chat.isSuccessful) chat.result?.get("members") as? List<*> else null
                    val prefs = context.getSharedPreferences("wake_received", Context.MODE_PRIVATE)
                    val events = prefs.getString("events_$uid", "")!!.split(',').filter { it.isNotEmpty() }
                    if (members?.size == 2 && members.contains(uid) && members.contains(sender)
                        && FirebaseAuth.getInstance().currentUser?.uid == uid && eventId !in events) {
                        val volume = (settings?.get("volume") as? Number)?.toDouble()?.coerceIn(0.0, 1.0) ?: 0.3
                        val alarm = Intent(context, WakeAlarmService::class.java).putExtra("uid", uid).putExtra("volume", volume)
                        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(alarm) else context.startService(alarm)
                        prefs.edit().putString("events_$uid", (events.takeLast(19) + eventId).joinToString(",")).apply()
                    }
                } catch (_: Exception) { /* OS background restrictions win; never bypass them. */ }
                finally { pending.finish() }
            }
        }
    }
}

class WakeAlarmService : Service() {
    companion object { @Volatile var active = false; private set }
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { stopSelf(); return START_NOT_STICKY }
        val local=intent?.action=="local"
        val preference=if(local)"flutter.personal_reminders_enabled" else "flutter.alarm_notifications_enabled"
        if(!getSharedPreferences("FlutterSharedPreferences",MODE_PRIVATE).getBoolean(preference,true)){stopSelf();return START_NOT_STICKY}
        val uid = intent?.getStringExtra("uid")
        if (local) { if(!LocalReminders.consume(this,intent?.getStringExtra("reminderId"))){stopSelf();return START_NOT_STICKY} }
        else if (uid == null || FirebaseAuth.getInstance().currentUser?.uid != uid) { stopSelf(); return START_NOT_STICKY }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel("wakeup_alarm", "Uyandırma alarmı", NotificationManager.IMPORTANCE_HIGH)
            channel.setSound(null, null); channel.setShowBadge(false); channel.lockscreenVisibility = Notification.VISIBILITY_SECRET
            manager.createNotificationChannel(channel)
        }
        val screen = PendingIntent.getActivity(this, 1, Intent(this, WakeAlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "wakeup_alarm") else Notification.Builder(this)
        val wantsFullScreen = true
        if (wantsFullScreen && (Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent())) notification.setFullScreenIntent(screen, true)
        active = true
        startForeground(33902, notification.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Hatırlatma").setContentText("Alarm ekranını açmak için dokun.")
            .setCategory(Notification.CATEGORY_ALARM).setPriority(Notification.PRIORITY_HIGH)
            .setVisibility(Notification.VISIBILITY_SECRET).setContentIntent(screen).setOngoing(true).build())
        if (player != null) return START_NOT_STICKY
        val volume = (intent?.getDoubleExtra("volume", 0.3) ?: 0.3).coerceIn(0.0, 1.0).toFloat()
        try {
            val audio = MediaPlayer()
            player = audio
            audio.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            audio.setDataSource(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            audio.setVolume(volume, volume); audio.isLooping = true
            audio.setOnPreparedListener { it.start() }
            audio.setOnErrorListener { _, _, _ -> stopSelf(); true }
            audio.prepareAsync()
            handler.postDelayed({ stopSelf() }, 20000)
        } catch (_: Exception) { stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        active = false
        stopForeground(true)
        handler.removeCallbacksAndMessages(null)
        try { player?.release() } catch (_: Exception) {}
        player = null
        super.onDestroy()
    }
}
