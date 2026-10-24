package com.melek.stargaleri

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.*
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

object VoiceCallBridge {
    fun enabled(context: Context, video: Boolean): Boolean {
        val local = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return local.getBoolean(if(video) "flutter.video_call_notifications_enabled" else "flutter.voice_call_notifications_enabled", local.getBoolean("flutter.call_notifications_enabled", true))
    }
    var channel: MethodChannel? = null
    private var pending: String? = null
    const val ANSWER = "com.melek.stargaleri.ANSWER_CALL"
    fun notificationId(id: String) = (id.hashCode() and 0x3fffffff) + 1000
    fun event(method: String, id: String) { Handler(Looper.getMainLooper()).post { channel?.invokeMethod(method, id) } }
    fun capture(context: Context, intent: Intent?) {
        if (intent?.action != ANSWER) return
        val id = intent.getStringExtra("callId") ?: return
        val nonce = intent.getStringExtra("nonce") ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        if (!Regex("^[A-Za-z0-9]{20}$").matches(id) || intent.getStringExtra("uid") != uid) return
        val prefs = context.getSharedPreferences("call_notifications", Context.MODE_PRIVATE)
        if (prefs.getString("nonce_$id", null) != nonce) return
        prefs.edit().remove("nonce_$id").apply()
        pending = id
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notificationId(id))
        event("answer", id)
    }
    fun consume(): String? { val value = pending; pending = null; return value }
}

class VoiceMessageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val type = intent.getStringExtra("type")
        if (type != "voice_call" && type != "voice_call_end") return
        val id = intent.getStringExtra("callId") ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        if (!Regex("^[A-Za-z0-9]{20}$").matches(id) || intent.getStringExtra("recipientUid") != uid) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (type == "voice_call_end") { manager.cancel(VoiceCallBridge.notificationId(id)); context.getSharedPreferences("call_notifications",Context.MODE_PRIVATE).edit().remove("nonce_$id").apply(); return }
        val local = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!local.getBoolean("flutter.feature_access_calls", true) || !local.getBoolean("flutter.feature_access_microphone", true)) return
        if (!local.getBoolean("flutter.background_calls_$uid", false)) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        if (!manager.areNotificationsEnabled()) return
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) return
        val pending = goAsync()
        val finished = AtomicBoolean(false)
        val handler = Handler(Looper.getMainLooper())
        val timeout = Runnable { if (finished.compareAndSet(false, true)) pending.finish() }
        handler.postDelayed(timeout, 8000)
        val db = NativeDocuments
        db.document("voiceCalls/$id").get().addOnCompleteListener { result ->
            val call = if (result.isSuccessful) result.result?.data else null
            val created = (call?.get("createdAt") as? com.google.firebase.Timestamp)?.toDate()?.time
            if (finished.get()) return@addOnCompleteListener
            if (call?.get("callee") != uid || call["state"] != "ringing" || created == null || System.currentTimeMillis()-created !in 0..45000) {
                if (finished.compareAndSet(false,true)) { handler.removeCallbacks(timeout); pending.finish() }; return@addOnCompleteListener
            }
            if (call["sourceType"] == "couple" && (local.getString("flutter.couple_id",null) != call["sourceId"] || local.getString("flutter.couple_secret",null).isNullOrEmpty())) {
                if (finished.compareAndSet(false,true)) { handler.removeCallbacks(timeout); pending.finish() }; return@addOnCompleteListener
            }
            val device = local.getString("flutter.wakeup_device_id",null)
            if (device == null) { if(finished.compareAndSet(false,true)){handler.removeCallbacks(timeout);pending.finish()};return@addOnCompleteListener }
            db.document("chatAccounts/$uid/callDevices/$device").get().addOnCompleteListener consent@ { settings ->
                if (!finished.compareAndSet(false,true)) return@consent
                handler.removeCallbacks(timeout)
                try {
                    if (settings.isSuccessful && settings.result?.getBoolean("enabled") == true && FirebaseAuth.getInstance().currentUser?.uid == uid && local.getBoolean("flutter.background_calls_$uid",false)) {
                        showIncoming(context, manager, uid, id, created, call["video"]==true)
                    }
                } catch (_: Exception) { /* Notification permission can change while loading. */ }
                finally { pending.finish() }
            }
        }
    }
    private fun showIncoming(context: Context, manager: NotificationManager, uid: String, id: String, created: Long, video: Boolean) {
        // A delayed push must not announce an already active call as incoming.
        if (VoiceOngoingService.activeId != null) return
        if(!VoiceCallBridge.enabled(context,video))return
        val prefs = context.getSharedPreferences("call_notifications", Context.MODE_PRIVATE)
        if (prefs.getLong("seen_$id",0L) > System.currentTimeMillis()-45000) return
        val nonce = UUID.randomUUID().toString()
        prefs.edit().putLong("seen_$id",System.currentTimeMillis()).putString("nonce_$id",nonce).apply()
        val ringtoneChannel = CallRingtone.channel(context)
        if (CallRingtone.blocked(context)) return
        val screenIntent=Intent(context,IncomingCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("callId",id).putExtra("uid",uid).putExtra("nonce",nonce).putExtra("created",created).putExtra("video",video)
        val screen=PendingIntent.getActivity(context,VoiceCallBridge.notificationId(id)+1,screenIntent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val decline = PendingIntent.getBroadcast(context, VoiceCallBridge.notificationId(id),
            Intent(context, VoiceCallDeclineReceiver::class.java).putExtra("callId",id).putExtra("uid",uid), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val local=context.getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE)
        val title=local.getString("flutter.incoming_call_title",null)?.trim()?.take(80)?.takeIf { it.isNotEmpty() } ?: "Gelen arama"
        val text=local.getString("flutter.incoming_call_body",null)?.trim()?.take(160)?.takeIf { it.isNotEmpty() } ?: "Yanıtlamak için dokun."
        val builder = if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,ringtoneChannel) else Notification.Builder(context)
        builder.setSmallIcon(com.melek.stargaleri.R.mipmap.ic_neural).setContentTitle(title)
            .setContentText(text).setCategory(Notification.CATEGORY_CALL).setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(screen).setAutoCancel(true).setDeleteIntent(decline)
            .addAction(Notification.Action.Builder(null,"Arama ekranını aç",screen).build())
            .addAction(Notification.Action.Builder(null,"Reddet",decline).build())
        if(local.getBoolean("flutter.call_fullscreen",true)&&(Build.VERSION.SDK_INT<34||manager.canUseFullScreenIntent()))builder.setFullScreenIntent(screen,true)
        if(Build.VERSION.SDK_INT>=26)builder.setTimeoutAfter((45000-(System.currentTimeMillis()-created)).coerceAtLeast(1))
        CallRingtone.legacySound(context, builder)
        val notification=builder.build()
        notification.flags=notification.flags or Notification.FLAG_INSISTENT
        manager.notify(VoiceCallBridge.notificationId(id),notification)
    }
}

class VoiceCallDeclineReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("callId") ?: return
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        if (!Regex("^[A-Za-z0-9]{20}$").matches(id) || intent.getStringExtra("uid") != uid) return
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(VoiceCallBridge.notificationId(id))
        val pending = goAsync()
        val done=AtomicBoolean(false)
        val handler=Handler(Looper.getMainLooper())
        val timeout=Runnable{if(done.compareAndSet(false,true))pending.finish()}
        handler.postDelayed(timeout,8000)
        NativeDocuments.document("voiceCalls/$id").update(mapOf("state" to "ended", "endedAt" to FieldValue.serverTimestamp()))
            .addOnCompleteListener { if(done.compareAndSet(false,true)){handler.removeCallbacks(timeout);pending.finish()} }
    }
}

class VoiceOngoingService : Service() {
    companion object { var activeId: String? = null; private set }
    private val handler = Handler(Looper.getMainLooper())
    private var id: String? = null
    private var connectedAt: Long? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable { id?.let { VoiceCallBridge.event("timeout",it) }; stopSelf() }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getStringExtra("callId") ?: return START_NOT_STICKY
        if (intent.action == "stop") { VoiceCallBridge.event("stop",callId); stopSelf(); return START_NOT_STICKY }
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid == null || uid != intent.getStringExtra("uid") || (id != null && id != callId)) { stopSelf(); return START_NOT_STICKY }
        id = callId
        activeId = callId
        if(intent.action=="connected"){
            if(connectedAt==null)connectedAt=SystemClock.elapsedRealtime()
            handler.removeCallbacks(timeout)
            return START_NOT_STICKY
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel("ongoing_call_quiet","Devam eden arama",NotificationManager.IMPORTANCE_MIN)
            channel.lockscreenVisibility=Notification.VISIBILITY_SECRET; channel.setSound(null,null); channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
        val stop = PendingIntent.getService(this, 1717, Intent(this,VoiceOngoingService::class.java).setAction("stop").putExtra("callId",callId),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this,1718,Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder=if(Build.VERSION.SDK_INT>=26)Notification.Builder(this,"ongoing_call_quiet")else Notification.Builder(this)
        val notification=builder.setSmallIcon(R.mipmap.ic_neural).setContentTitle("Arama sürüyor").setContentText("Bitirmek için dokun.")
            .setVisibility(Notification.VISIBILITY_SECRET).setOngoing(true).setContentIntent(open)
            .setPriority(Notification.PRIORITY_MIN).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null,"Aramayı bitir",stop).build()).build()
        try {
            if(Build.VERSION.SDK_INT>=30)startForeground(1717,notification,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or (if(intent.getBooleanExtra("video",false))android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0))
            else startForeground(1717,notification)
        }catch(_:Exception){VoiceCallBridge.event("stopped",callId);stopSelf();return START_NOT_STICKY}
        manager.cancel(VoiceCallBridge.notificationId(callId))
        if(wakeLock==null){wakeLock=(getSystemService(Context.POWER_SERVICE)as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"Neural:VoiceCall").apply{acquire()}}
        handler.removeCallbacks(timeout)
        if(connectedAt==null)handler.postDelayed(timeout,60000)
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { id?.let { VoiceCallBridge.event("stop",it) }; stopSelf() }
    override fun onDestroy(){handler.removeCallbacks(timeout);if(wakeLock?.isHeld==true)wakeLock?.release();wakeLock=null;id?.let{VoiceCallBridge.event("stopped",it)};if(activeId==id)activeId=null;super.onDestroy()}
}
