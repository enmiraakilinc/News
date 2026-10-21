package com.melek.stargaleri

import android.view.WindowManager
import android.os.Bundle
import android.content.Context
import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    var microphoneStartAllowed = false; private set
    override fun onResume() { super.onResume(); microphoneStartAllowed = true }
    override fun onPause() { microphoneStartAllowed = false; super.onPause() }

    private lateinit var videoParts: VideoParts
    private val secureChannel = "app/secure_screen"
    private var locationResult: MethodChannel.Result? = null
    private var locationCancellation: CancellationSignal? = null
    private var locationListener: LocationListener? = null
    private val locationHandler = Handler(Looper.getMainLooper())
    private var locationTimeout: Runnable? = null

    private fun finishLocation(location: Location?, code: String = "unavailable") {
        val result = locationResult ?: return
        locationResult = null
        locationTimeout?.let { locationHandler.removeCallbacks(it) }
        locationTimeout = null
        locationCancellation?.cancel()
        locationCancellation = null
        locationListener?.let {
            (getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(it)
        }
        locationListener = null
        if (location == null) result.error(code, "Konum alinamadi", null)
        else result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude))
    }

    @Suppress("MissingPermission", "DEPRECATION")
    private fun readLocation() {
        if (locationResult == null) return
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val precise = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        // A recent fix avoids cold GPS starts and works with approximate access.
        val recent = manager.getProviders(true).mapNotNull { provider ->
            try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null }
        }.filter { System.currentTimeMillis() - it.time in 0..120000 }
            .minByOrNull { it.accuracy }
        if (recent != null) { finishLocation(recent); return }
        val provider = when {
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            precise && manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            else -> { finishLocation(null, "disabled"); return }
        }
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                val cancellation = CancellationSignal()
                locationCancellation = cancellation
                manager.getCurrentLocation(provider, cancellation,
                    Executor { task -> runOnUiThread(task) }) { location -> finishLocation(location) }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) { finishLocation(location) }
                    override fun onProviderDisabled(provider: String) { finishLocation(null, "disabled") }
                    override fun onProviderEnabled(provider: String) {}
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                }
                locationListener = listener
                manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }
        } catch (_: Exception) { finishLocation(null) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 7101 || locationResult == null) return
        if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) readLocation()
        else finishLocation(null, "denied")
    }

    override fun onDestroy() {
        if (MicrophoneSessionService.mode == "voice") stopService(android.content.Intent(this, MicrophoneSessionService::class.java))
        MicrophoneSessionBridge.channel?.setMethodCallHandler(null)
        MicrophoneSessionBridge.channel = null
        stopService(android.content.Intent(this, VoiceOngoingService::class.java))
        VoiceCallBridge.channel = null
        if (::videoParts.isInitialized) videoParts.close()
        finishLocation(null, "cancelled")
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        // Widget provider was removed from the manifest; discard its old data.
        getSharedPreferences("counter_widget", Context.MODE_PRIVATE).edit().clear().apply()
        super.onCreate(savedInstanceState)
        VoiceCallBridge.capture(this, intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        VoiceCallBridge.capture(this, intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AudioFilesBridge.attach(this, flutterEngine)
        MicrophoneSessionBridge.attach(this, flutterEngine)
        val voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/voice_call")
        VoiceCallBridge.channel = voiceChannel
        voiceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> result.success(VoiceCallBridge.consume())
                "disableIncoming" -> {
                    val manager=getSystemService(Context.NOTIFICATION_SERVICE)as android.app.NotificationManager
                    for(notification in manager.activeNotifications){
                        val incoming=if(Build.VERSION.SDK_INT>=26)notification.notification.channelId=="incoming_calls" else notification.notification.category==android.app.Notification.CATEGORY_CALL
                        if(incoming)manager.cancel(notification.id)
                    }
                    getSharedPreferences("call_notifications",Context.MODE_PRIVATE).edit().clear().apply()
                    result.success(null)
                }
                "cancelIncoming" -> { call.argument<String>("id")?.let { (getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).cancel(VoiceCallBridge.notificationId(it)) };result.success(null) }
                "stop" -> { if(call.argument<String>("id")==VoiceOngoingService.activeId)stopService(android.content.Intent(this,VoiceOngoingService::class.java));result.success(null) }
                "start", "connected" -> {
                    val id=call.argument<String>("id")
                    val uid=com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
                    if(id==null||!Regex("^[A-Za-z0-9]{20}$").matches(id)||uid==null){result.error("invalid","Arama bulunamadı.",null);return@setMethodCallHandler}
                    try {
                        val service=android.content.Intent(this,VoiceOngoingService::class.java).setAction(call.method)
                            .putExtra("callId",id).putExtra("uid",uid).putExtra("video",call.argument<Boolean>("video")?:false).putExtra("remaining",call.argument<Number>("remaining")?.toLong()?:900000)
                        if(call.method=="connected"){
                            if(VoiceOngoingService.activeId!=id){result.error("not_active","Arama sona erdi.",null);return@setMethodCallHandler}
                            startService(service)
                        }else if(Build.VERSION.SDK_INT>=26)startForegroundService(service)else startService(service)
                        result.success(true)
                    }catch(_:Exception){result.error("blocked","Arka planda arama başlatılamadı. Bildirim ve mikrofon izinlerini kontrol et.",null)}
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/permissions").setMethodCallHandler { call, result ->
            fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            when (call.method) {
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                "status" -> result.success(mapOf(
                    "camera" to granted(Manifest.permission.CAMERA),
                    "microphone" to granted(Manifest.permission.RECORD_AUDIO),
                    "notifications" to (getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).areNotificationsEnabled(),
                    "location" to (granted(Manifest.permission.ACCESS_COARSE_LOCATION) || granted(Manifest.permission.ACCESS_FINE_LOCATION))))
                "notificationSettings" -> {
                    val settingsIntent = if (Build.VERSION.SDK_INT >= 26) android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                    else android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:$packageName"))
                    startActivity(settingsIntent); result.success(null)
                }
                "settings" -> { startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    android.net.Uri.parse("package:$packageName"))); result.success(null) }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/wakeup").setMethodCallHandler { call, result ->
            if (call.method == "fullScreenAllowed") {
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                result.success(Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent())
            } else if (call.method == "fullScreenSettings") {
                if (Build.VERSION.SDK_INT >= 34) startActivity(android.content.Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, android.net.Uri.parse("package:$packageName")))
                result.success(null)
            } else if (call.method == "stop") {
                stopService(android.content.Intent(this, WakeAlarmService::class.java)); result.success(null)
            } else if (call.method == "preview") {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    result.error("denied", "Bildirim izni gerekli.", null)
                    return@setMethodCallHandler
                }
                val uid = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
                if (uid == null) result.error("signed_out", "Giriş gerekli.", null)
                else {
                    val alarm = android.content.Intent(this, WakeAlarmService::class.java)
                        .putExtra("uid", uid).putExtra("volume", call.argument<Number>("volume")?.toDouble() ?: 0.3)
                    try {
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(alarm) else startService(alarm)
                        result.success(null)
                    } catch (_: Exception) { result.error("blocked", "Ses başlatılamadı. Bildirim iznini kontrol et.", null) }
                }
            } else result.notImplemented()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/reminders").setMethodCallHandler { call, result -> LocalReminders.handle(this,call,result) }
        videoParts = VideoParts(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/camera_light")
            .setMethodCallHandler { call, result ->
                if (call.method != "set") result.notImplemented()
                else {
                    val params = window.attributes
                    params.screenBrightness = if (call.argument<Boolean>("enabled") == true) 1f else -1f
                    window.attributes = params
                    result.success(null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/video_parts")
            .setMethodCallHandler { call, result ->
                if (call.method != "split") result.notImplemented()
                else videoParts.split(call.argument<String>("path"),
                    call.argument<Number>("maxBytes")?.toLong() ?: 0L, result)
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/location")
            .setMethodCallHandler { call, result ->
                if (call.method == "cancel") {
                    finishLocation(null, "cancelled")
                    result.success(null)
                } else if (call.method != "current") result.notImplemented()
                else if (!getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.feature_access_location", true)) result.error("disabled", "Konum kullanımı uygulama ayarlarında kapalı.", null)
                else if (locationResult != null) result.error("busy", "Konum istegi suruyor", null)
                else {
                    locationResult = result
                    val timeout = Runnable { finishLocation(null, "timeout") }
                    locationTimeout = timeout
                    locationHandler.postDelayed(timeout, 20000)
                    if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) readLocation()
                    else requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION), 7101)
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            secureChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // FLAG_SECURE: ekran goruntusunu ve son-kullanilanlar
                // onizlemesini engeller.
                "enable" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "disable" -> {
                    // Capture protection stays active on every application screen.
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
