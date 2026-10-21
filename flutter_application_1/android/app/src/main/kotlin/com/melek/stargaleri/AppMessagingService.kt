package com.melek.stargaleri

import android.content.Intent
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
        if (message.data["type"] == "wake") {
            val wake = Intent(this, WakeMessageReceiver::class.java)
            message.data.forEach { (key, value) -> wake.putExtra(key, value) }
            // Explicit, same-UID broadcast; no public or unprotected entry point.
            sendBroadcast(wake)
        }
        super.onMessageReceived(message)
    }
}
