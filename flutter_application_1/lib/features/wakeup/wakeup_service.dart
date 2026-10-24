import '../reminders/reminder_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../../core/notifications/notification_permission.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';
import '../../core/utils/user_errors.dart';

class WakeupService {
  static const channel = MethodChannel('app/wakeup');
  static StreamSubscription<String>? _refresh;
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('wakeup_device_id');
    if (saved != null) return saved;
    final random = Random.secure();
    final value = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString('wakeup_device_id', value);
    return value;
  }

  static String permissionId(String sourceKey, String device) =>
      sha256.convert(utf8.encode('$sourceKey/$device')).toString();
  static DocumentReference<Map<String, dynamic>> permission(
    String sourceKey,
    String device,
  ) => FirebaseFirestore.instance
      .collection('chatAccounts')
      .doc(CoupleService.uid!)
      .collection('wakePermissions')
      .doc(permissionId(sourceKey, device));
  static Future<String?> endpoint() async {
    if (const bool.fromEnvironment('NEURAL_POSTGRES_PRIMARY')) {
      return 'https://138.2.185.151';
    }
    try {
      final data =
          (await FirebaseFirestore.instance
                  .doc('config/wakeup')
                  .get(const GetOptions(source: Source.server)))
              .data();
      final uri = Uri.tryParse(data?['endpoint'] as String? ?? '');
      if (data?['enabled'] == true &&
          uri?.scheme == 'https' &&
          uri!.host.isNotEmpty) {
        return uri.toString();
      }
    } catch (_) {}
    return null;
  }

  static Future<void> register() async {
    final uid = CoupleService.uid;
    if (uid == null) return;
    final device = await deviceId();
    Future<void> save(String token) async {
      if (CoupleService.uid != uid) return;
      await FirebaseFirestore.instance
          .doc('chatAccounts/$uid/wakeDevices/$device')
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw Exception(
        'Bildirim bağlantısı kurulamadı. Biraz sonra yeniden dene.',
      );
    }
    await save(token);
    await _refresh?.cancel();
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((value) {
      save(value).catchError((_) {});
    });
  }

  static Future<void> restoreRegistration() async {
    final uid = CoupleService.uid;
    if (uid == null) return;
    if ((await SharedPreferences.getInstance()).getBool('wakeup_used_$uid') !=
        true) {
      return;
    }
    try {
      await register();
    } catch (_) {}
  }

  static Future<String> send(
    String sourceKey, {
    DateTime? fireAt,
    bool cancel = false,
  }) async {
    await CoupleService.ensureReady();
    final url = await endpoint();
    if (url == null) throw Exception('Uyandırma hizmeti henüz etkin değil.');
    final parts = sourceKey.split('/');
    final data =
        (await FirebaseFirestore.instance
                .collection(parts[0] == 'chat' ? 'chats' : 'couples')
                .doc(parts[1])
                .get())
            .data();
    final members = List<String>.from(data?['members'] ?? []);
    final uid = CoupleService.uid;
    if (members.length != 2 || !members.contains(uid)) {
      throw Exception('Uyandırma yalnızca birebir sohbetlerde kullanılabilir.');
    }
    final recipient = members.firstWhere((id) => id != uid);
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    final response = await http
        .post(
          Uri.parse(
            '$url/nudge${cancel
                ? '/cancel'
                : fireAt != null
                ? '/schedule'
                : ''}',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'sourceKey': sourceKey,
            'recipientUid': recipient,
            if (fireAt != null) 'fireAt': fireAt.millisecondsSinceEpoch,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final result = jsonDecode(response.body) as Map;
    final message = result['message'] ?? (result['error'] as Map?)?['message'];
    if (message is! String || message.length > 250) {
      throw Exception('Uyandırma isteği gönderilemedi. Yeniden dene.');
    }
    if (response.statusCode != 200) throw Exception(message);
    return message;
  }
}

class WakeupSettings extends StatefulWidget {
  final String sourceKey;
  const WakeupSettings({super.key, required this.sourceKey});
  @override
  State<WakeupSettings> createState() => _WakeupSettingsState();
}

class _WakeupSettingsState extends State<WakeupSettings> {
  bool _ready = false, _loading = true, _enabled = false, _busy = false;
  double _volume = 0.3;
  String? _device;
  bool _locallyDisabled = false;
  String get _disabledKey =>
      'wakeup_disabled_${CoupleService.uid}_${WakeupService.permissionId(widget.sourceKey, _device!)}';
  StreamSubscription? _settings;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await CoupleService.ensureReady();
      _device = await WakeupService.deviceId();
      _locallyDisabled =
          (await SharedPreferences.getInstance()).getBool(_disabledKey) ??
          false;
      _ready = await WakeupService.endpoint() != null;
      if (!mounted) return;
      _settings = WakeupService.permission(widget.sourceKey, _device!)
          .snapshots()
          .listen(
            (snap) {
              if (mounted) {
                setState(() {
                  _enabled =
                      snap.data()?['enabled'] == true && !_locallyDisabled;
                  _volume = (snap.data()?['volume'] as num? ?? 0.3)
                      .toDouble()
                      .clamp(0, 1);
                });
              }
            },
            onError: (_) {
              if (mounted) setState(() => _ready = false);
            },
          );
    } catch (_) {
      _ready = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _settings?.cancel();
    super.dispose();
  }

  Future<void> _save(bool enabled) async {
    if (_busy || !_ready || _device == null) return;
    setState(() => _busy = true);
    try {
      if (!enabled) {
        _locallyDisabled = true;
        await (await SharedPreferences.getInstance()).setBool(
          _disabledKey,
          true,
        );
        if (mounted) setState(() => _enabled = false);
        await WakeupService.channel.invokeMethod('stop');
      }
      if (enabled) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('alarm_notifications_enabled') == false) {
          if (!mounted) return;
          final allow = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Uyandırma alarmlarını aç?'),
              content: const Text(
                'Bu kişiye izin vermek için genel uyandırma ayarı da açık olmalı. Mesaj ve diğer içerik bildirimleri değişmez.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Aç'),
                ),
              ],
            ),
          );
          if (allow != true) return;
          if (!mounted || !await ensureNotificationPermission(context)) return;
          await prefs.setBool('alarm_notifications_enabled', true);
        } else {
          if (!mounted || !await ensureNotificationPermission(context)) return;
        }
        if (!mounted || !await ReminderService.fullScreenAccess(context)) {
          return;
        }
        await WakeupService.register();
      }
      await WakeupService.permission(widget.sourceKey, _device!)
          .set({
            'sourceKey': widget.sourceKey,
            'deviceId': _device,
            'enabled': enabled,
            'volume': _volume,
          })
          .timeout(const Duration(seconds: 20));
      if (enabled) {
        await (await SharedPreferences.getInstance()).setBool(
          'wakeup_used_${CoupleService.uid}',
          true,
        );
        _locallyDisabled = false;
        await (await SharedPreferences.getInstance()).setBool(
          _disabledKey,
          false,
        );
      }
      if (mounted) setState(() => _enabled = enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: const Text('Bu kişi beni uyandırabilsin'),
        subtitle: Text(
          _loading
              ? 'Ayar yükleniyor…'
              : !_ready
              ? 'Uyandırma hizmeti henüz etkin değil.'
              : 'Yalnızca bu telefon için. Kapalıyken kimse buradan alarm çaldıramaz.',
        ),
        value: _enabled,
        onChanged: _ready && !_busy && !_loading ? _save : null,
      ),
      if (_ready) ...[
        ListTile(
          leading: const Icon(Icons.alarm),
          title: const Text('Tam ekran alarm'),
          subtitle: const Text(
            'Kilit ekranında Alarmı kapat ekranı açılır. Android tam ekran izni gerekir; sistem bazen bildirim gösterebilir.',
          ),
          trailing: TextButton(
            onPressed: () => ReminderService.fullScreenAccess(context),
            child: const Text('İzni kontrol et'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Alarm en fazla 20 saniye çalar. Android ekran açıkken tam ekran yerine bildirim gösterebilir. İnternet, izinler ve pil ayarları ulaşmasını etkiler.',
          ),
        ),
        ListTile(
          title: const Text('Uyandırma sesi'),
          subtitle: Slider(
            value: _volume,
            onChanged: _busy ? null : (v) => setState(() => _volume = v),
            onChangeEnd: _enabled ? (_) => _save(true) : null,
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _enabled && !_busy
                  ? () async {
                      try {
                        await WakeupService.channel.invokeMethod('preview', {
                          'volume': _volume,
                        });
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(userError(error))),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Sesi dene'),
            ),
            TextButton(
              onPressed: () => WakeupService.channel.invokeMethod('stop'),
              child: const Text('Sesi durdur'),
            ),
          ],
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Anında çal'),
          subtitle: const Text(
            'Yalnızca karşı taraf bu sohbet için izin verdiyse.',
          ),
          onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final message = await WakeupService.send(widget.sourceKey);
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userError(error))));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Zamanlamalı çal'),
          subtitle: const Text(
            'Önümüzdeki 24 saat için. Bu kişi başına bir plan; çalma anında izni yeniden kontrol edilir.',
          ),
          onTap: _busy
              ? null
              : () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time == null || !mounted) return;
                  final now = DateTime.now();
                  var at = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    time.hour,
                    time.minute,
                  );
                  if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
                  setState(() => _busy = true);
                  try {
                    final message = await WakeupService.send(
                      widget.sourceKey,
                      fireAt: at,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${time.format(context)}: $message'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userError(error))));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final message = await WakeupService.send(
                      widget.sourceKey,
                      cancel: true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userError(error))));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Zamanlanmış alarmı iptal et'),
        ),
      ],
    ],
  );
}
