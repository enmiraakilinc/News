import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';
import '../wakeup/wakeup_service.dart';
import '../../core/utils/user_errors.dart';
import '../../core/notifications/notification_permission.dart';

class NativeCallEvent {
  final String method, id;
  NativeCallEvent(this.method, this.id);
}

class CallBackground {
  static const channel = MethodChannel('app/voice_call');
  static final events = StreamController<NativeCallEvent>.broadcast();
  static StreamSubscription<String>? _refresh;
  static bool _initialized = false;
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.arguments is String) {
        events.add(NativeCallEvent(call.method, call.arguments as String));
      }
    });
  }

  static Future<bool> notificationAllowed() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<void> register(
    bool enabled, {
    bool requestPermission = true,
  }) async {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid!;
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool('background_calls_$uid', false);
      try {
        await channel.invokeMethod('disableIncoming');
      } catch (_) {}
    }
    if (enabled && !await notificationAllowed()) {
      if (requestPermission) {
        await FirebaseMessaging.instance.requestPermission();
      }
      if (!await notificationAllowed()) {
        throw Exception(
          'Uygulama kapalıyken arama almak için telefon ayarlarından bildirim iznini açmalısın.',
        );
      }
    }
    final device = await WakeupService.deviceId();
    final ref = FirebaseFirestore.instance.doc(
      'chatAccounts/$uid/callDevices/$device',
    );
    if (!enabled) {
      if ((await ref.get()).exists) {
        await ref.update({
          'enabled': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await _refresh?.cancel();
      return;
    }
    Future<void> save(String token) async {
      if (CoupleService.uid != uid) return;
      await ref.set({
        'token': token,
        'enabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw Exception('Arama bildirim bağlantısı kurulamadı. Yeniden dene.');
    }
    await save(token);
    if (CoupleService.uid != uid) return;
    await prefs.setBool('background_calls_$uid', true);
    await _refresh?.cancel();
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((value) async {
      if (prefs.getBool('background_calls_$uid') == true) {
        await save(value).catchError((_) {});
      }
    });
  }

  static Future<void> restore() async {
    final uid = CoupleService.uid;
    if (uid != null &&
        (await SharedPreferences.getInstance()).getBool(
              'background_calls_$uid',
            ) ==
            true) {
      await register(true, requestPermission: false);
    }
  }

  static Future<void> notify(String id, String action) async {
    final endpoint = await WakeupService.endpoint();
    if (endpoint == null) return;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return;
    final response = await http
        .post(
          Uri.parse('$endpoint/call'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'id': id, 'action': action}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && action == 'ring') {
      throw Exception(
        'Arama bildirimi iletilemedi. Karşı taraf uygulamayı açarak yanıtlayabilir.',
      );
    }
  }

  static Future<bool> start(String id, {bool video = false}) async {
    try {
      if (!await notificationAllowed()) return false;
      return await channel.invokeMethod<bool>('start', {
            'id': id,
            'video': video,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> connected(String id, Duration remaining) async {
    try {
      await channel.invokeMethod('connected', {
        'id': id,
        'remaining': remaining.inMilliseconds,
      });
    } catch (_) {}
  }

  static Future<void> stop(String id) async {
    try {
      await channel.invokeMethod('stop', {'id': id});
    } catch (_) {}
  }

  static Future<void> cancelIncoming(String id) async {
    try {
      await channel.invokeMethod('cancelIncoming', {'id': id});
    } catch (_) {}
  }
}

class BackgroundCallSwitch extends StatefulWidget {
  const BackgroundCallSwitch({super.key});
  @override
  State<BackgroundCallSwitch> createState() => _BackgroundCallSwitchState();
}

class _BackgroundCallSwitchState extends State<BackgroundCallSwitch> {
  bool _enabled = false, _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await CoupleService.ensureReady();
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(
          () => _enabled =
              prefs.getBool('background_calls_${CoupleService.uid}') ?? false,
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Uygulama kapalıyken arama al'),
    subtitle: const Text(
      'Yalnızca bu telefon için. Arayanın adı yazmayan bir arama bildirimi gösterilir; mikrofon ancak Yanıtla’ya bastığında açılır. Telefonun bildirim ve pil izinleri gerekir.',
    ),
    value: _enabled,
    onChanged: _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              if (value && !await ensureNotificationPermission(context)) return;
              await CallBackground.register(
                value,
                requestPermission: false,
              ).timeout(const Duration(seconds: 20));
              if (mounted) setState(() => _enabled = value);
            } catch (error) {
              if (!value && mounted) setState(() => _enabled = false);
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(error))));
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
