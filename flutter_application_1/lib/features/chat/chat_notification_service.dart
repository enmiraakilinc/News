// Sohbet bildirimini cihaza yazar.
import 'dart:async';

import '../../core/utils/random_id.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pair/couple_service.dart';

class ChatNotificationService {
  static const _deviceKey = 'chat_notification_device_id';
  static StreamSubscription<String>? _tokenRefresh;

  static Future<void> sync(bool enabled) async {
    if (!enabled) {
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
    }
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_deviceKey);
    if (!enabled) {
      if (deviceId != null) {
        await FirebaseFirestore.instance
            .doc('chatAccounts/$uid/chatDevices/$deviceId')
            .delete();
      }
      return;
    }

    final device = deviceId ?? _newDeviceId();
    if (deviceId == null) await prefs.setString(_deviceKey, device);
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null) {
      throw StateError('Bildirim bağlantısı kurulamadı. Yeniden dene.');
    }

    Future<void> save(String value) async {
      if (CoupleService.uid != uid) return;
      await FirebaseFirestore.instance
          .doc('chatAccounts/$uid/chatDevices/$device')
          .set({'token': value, 'updatedAt': FieldValue.serverTimestamp()});
    }

    await save(token);
    await _tokenRefresh?.cancel();
    _tokenRefresh = messaging.onTokenRefresh.listen(
      (value) => save(value).catchError((Object error) {
        debugPrint('Chat notification token refresh failed: $error');
      }),
    );
  }

  static String _newDeviceId() => randomHex(16);
}
