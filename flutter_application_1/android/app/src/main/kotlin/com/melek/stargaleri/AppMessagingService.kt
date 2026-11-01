package com.melek.stargaleri

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * FCM's service entry point receives data-only wake messages even without a
 * running Dart isolate. The protected receiver still validates consent,
 * membership, freshness, notification settings and duplicate event IDs.
 * Inheriting Flutter's service preserves onNewToken/onTokenRefresh.
 */
class AppMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val receiver = when (message.data["type"]) {
            "wake" -> WakeMessageReceiver::class.java
            "voice_call", "voice_call_end" -> VoiceMessageReceiver::class.java
            else -> null
        }
        if (message.data["type"] == "chat") showChatNotification(message)
        if (receiver != null) {
            val wake = Intent(this, receiver)
            message.data.forEach { (key, value) -> wake.putExtra(key, value) }
            // Explicit, same-UID broadcast; no public or unprotected entry point.
            sendBroadcast(wake)
        }
        super.onMessageReceived(message)
    }

    private fun showChatNotification(message: RemoteMessage) {
        val recipient = message.data["recipientUid"] ?: return
        val eventId = message.data["eventId"] ?: return
        val preferences = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (preferences.getString("flutter.my_uid", null) != recipient) return
        val enabled = preferences.getBoolean(
            "flutter.content_notification_chats",
            preferences.getBoolean(
                "flutter.chat_notifications_enabled",
                preferences.getBoolean("flutter.push_bar_enabled", false)
            )
        )
        if (!enabled) return
        if (!NotificationManagerCompat.from(this).areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
        ) return

        val seen = getSharedPreferences("chat_push_events", Context.MODE_PRIVATE)
        val eventIds = seen.getStringSet("seen", emptySet())?.toMutableList() ?: mutableListOf()
        if (eventId in eventIds) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel("updates", "Güncellemeler", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }

        val customText = preferences.getString("flutter.tmpl_chat_messages", null)?.trim()
        val body = customText?.takeIf { it.isNotEmpty() } ?: "Yeni bir güncelleme mevcut."
        val openApp = PendingIntent.getActivity(
            this,
            898,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, "updates")
            .setSmallIcon(R.mipmap.ic_neural)
            .setContentTitle("Güncelleme")
            .setContentText(body)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(this).notify(898, notification)

        eventIds.add(eventId)
        seen.edit().putStringSet("seen", eventIds.takeLast(64).toSet()).apply()
    }
}
