// Sohbet bildirimini cihaza yazar.
import 'dart:async';

import '../../core/utils/random_id.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notif_prefs.dart';
import '../pair/couple_service.dart';

class ChatNotificationService {
  static const _deviceKey = 'chat_notification_device_id';
  static StreamSubscription<String>? _tokenRefresh;
  static String? _registeredFor;
  static bool _syncing = false;

  /// Oturum açılınca veya ilk deneme başarısız olunca bildirim kaydını
  /// sessizce yeniden dener; uygulamayı yeniden başlatmak gerekmez.
  static Future<void> ensureRegistered() async {
    final uid = CoupleService.uid;
    if (_syncing || uid == null || uid == _registeredFor) return;
    _syncing = true;
    try {
      await sync(await chatNotificationsEnabled());
    } catch (error) {
      debugPrint('Chat notification registration retry failed: $error');
    } finally {
      _syncing = false;
    }
  }

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
      _registeredFor = uid;
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
    _registeredFor = uid;
    await _tokenRefresh?.cancel();
    _tokenRefresh = messaging.onTokenRefresh.listen(
      (value) => save(value).catchError((Object error) {
        debugPrint('Chat notification token refresh failed: $error');
      }),
    );
  }

  static String _newDeviceId() => randomHex(16);
}
