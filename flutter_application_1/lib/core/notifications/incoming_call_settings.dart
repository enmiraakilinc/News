import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notif_prefs.dart';
import '../../features/calls/call_background.dart';
import 'notification_permission.dart';

Future<bool> incomingCallsEnabled({bool video = false}) async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(
        video
            ? 'video_call_notifications_enabled'
            : 'voice_call_notifications_enabled',
      ) ??
      p.getBool('call_notifications_enabled') ??
      true;
}

Future<void> setAlarmOnlyPreferences() async {
  final p = await SharedPreferences.getInstance();
  // Public news preferences are independent from the private area's presets.
  final news = await contentNotificationEnabled(kNotifNews);
  await p.setBool('content_notification_news', news);
  for (final kind in [
    kNotifChats,
    ...kAllContentNotifs,
    kNotifUpdates,
    kNotifStorage,
  ]) {
    await p.setBool('content_notification_${kind.collection}', false);
  }
  await p.setBool(kChatNotificationsKey, false);
  await p.setBool(kPushBarKey, false);
  await p.setBool('notif_active', false);
  await p.setBool('call_notifications_enabled', false);
  await p.setBool('voice_call_notifications_enabled', false);
  await p.setBool('video_call_notifications_enabled', false);
  await p.setBool('alarm_notifications_enabled', true);
}

class NotificationPreferenceSwitch extends StatefulWidget {
  const NotificationPreferenceSwitch({
    super.key,
    required this.preference,
    required this.title,
    required this.description,
    this.fullScreen = false,
  });
  final String preference, title, description;
  final bool fullScreen;
  @override
  State<NotificationPreferenceSwitch> createState() =>
      _NotificationPreferenceSwitchState();
}

class _NotificationPreferenceSwitchState
    extends State<NotificationPreferenceSwitch> {
  bool? _enabled;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(
          () => _enabled =
              p.getBool(widget.preference) ??
              ([
                    'voice_call_notifications_enabled',
                    'video_call_notifications_enabled',
                  ].contains(widget.preference)
                  ? p.getBool('call_notifications_enabled')
                  : null) ??
              true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(widget.title),
    subtitle: Text(widget.description),
    value: _enabled ?? false,
    onChanged: _enabled == null || _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              if (value && !widget.fullScreen) {
                if (!await ensureNotificationPermission(context)) return;
              }
              await (await SharedPreferences.getInstance()).setBool(
                widget.preference,
                value,
              );
              if (mounted) setState(() => _enabled = value);
              if (!value &&
                  widget.preference == 'alarm_notifications_enabled') {
                await const MethodChannel('app/wakeup').invokeMethod('stop');
              }
              if (!value && widget.preference == 'call_notifications_enabled') {
                await CallBackground.channel.invokeMethod('disableIncoming');
              }
              if (value && widget.fullScreen) {
                const channel = MethodChannel('app/wakeup');
                if (await channel.invokeMethod<bool>('fullScreenAllowed') !=
                    true) {
                  if (!context.mounted) return;
                  final open = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Tam ekran arama izni'),
                      content: const Text(
                        'Android tam ekran arama için özel izin istiyor. İlgili izin ekranını açalım mı?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Şimdi değil'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('İzni aç'),
                        ),
                      ],
                    ),
                  );
                  if (open == true) {
                    await channel.invokeMethod('fullScreenSettings');
                  }
                }
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Telefonun uygulama ayarlarından izinleri kontrol et.',
                    ),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}

class IncomingNotificationSettings extends StatelessWidget {
  const IncomingNotificationSettings({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Divider(),
      ListTile(title: Text('Aramalar')),
      NotificationPreferenceSwitch(
        preference: 'voice_call_notifications_enabled',
        title: 'Sesli arama bildirimleri',
        description: 'Mesaj ve diğer içerik bildirimlerinden bağımsızdır.',
      ),
      NotificationPreferenceSwitch(
        preference: 'video_call_notifications_enabled',
        title: 'Görüntülü arama bildirimleri',
        description: 'Sesli aramalardan bağımsız açılıp kapatılır.',
      ),
      BackgroundCallSwitch(),
      CallNotificationTextSetting(),
      NotificationPreferenceSwitch(
        preference: 'call_fullscreen',
        title: 'Tam ekran gelen arama',
        description:
            'Android özel erişim izni gerekir. Sistem tam ekranı göstermiyorsa bildirime dokunarak açılır.',
        fullScreen: true,
      ),
      ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Arama ekranı görüntü koruması'),
        subtitle: Text(
          'Sesli ve görüntülü aramalarda her zaman açık. Normal ekran görüntüsü ve ekran kaydı engellenir.',
        ),
        trailing: Icon(Icons.check_circle_outline),
      ),
      Divider(),
      ListTile(title: Text('Alarm / uyandırma')),
      NotificationPreferenceSwitch(
        preference: 'alarm_notifications_enabled',
        title: 'Uyandırma alarmları',
        description:
            'Yalnızca kişi ayrıntılarında izin verdiğin kişiler. Mesaj, anı ve soru bildirimlerini açmaz.',
      ),
    ],
  );
}

class CallNotificationTextSetting extends StatefulWidget {
  const CallNotificationTextSetting({super.key});
  @override
  State<CallNotificationTextSetting> createState() =>
      _CallNotificationTextSettingState();
}

class _CallNotificationTextSettingState
    extends State<CallNotificationTextSetting> {
  Future<void> _edit() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final title = TextEditingController(
      text: p.getString('incoming_call_title') ?? 'Gelen arama',
    );
    final body = TextEditingController(
      text: p.getString('incoming_call_body') ?? 'Yanıtlamak için dokun.',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arama bildirimi yazısı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Başlık'),
              ),
              TextField(
                controller: body,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Bildirim yazısı'),
              ),
              const Text(
                'Uygulama kapalıyken gelen sesli ve görüntülü arama bildirimlerinde kullanılır. Boş alanlar varsayılan yazıya döner.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (save == true) {
      await p.setString(
        'incoming_call_title',
        title.text.trim().isEmpty ? 'Gelen arama' : title.text.trim(),
      );
      await p.setString(
        'incoming_call_body',
        body.text.trim().isEmpty ? 'Yanıtlamak için dokun.' : body.text.trim(),
      );
    }
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      title.dispose();
      body.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.edit_notifications_outlined),
    title: const Text('Arama bildirimi yazısı'),
    subtitle: const Text(
      'Uygulama kapalıyken görünen başlığı ve yazıyı değiştir.',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: _edit,
  );
}

class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({super.key});
  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  int _revision = 0;
  bool _busy = false;
  Future<void> _alarmOnly() async {
    setState(() => _busy = true);
    try {
      final allowed = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (allowed == false) return;
      await setAlarmOnlyPreferences();
      for (final kind in [
        kNotifChats,
        ...kAllContentNotifs,
        kNotifNews,
        kNotifUpdates,
        kNotifStorage,
      ]) {
        await FlutterLocalNotificationsPlugin().cancel(kind.id);
      }
      await FlutterLocalNotificationsPlugin().cancel(888);
      await CallBackground.channel
          .invokeMethod('disableIncoming')
          .catchError((_) {});
      await FirebaseMessaging.instance
          .unsubscribeFromTopic('updates')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Yerel ayarlar kaydedildi; internet bağlantısını kontrol et.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _revision++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ListTile(
        title: Text('Bildirim tercihleri'),
        subtitle: Text(
          'Android bildirim izni yalnızca izin verir; hangi özelliğin bildireceğini buradan seçersin.',
        ),
      ),
      TextButton.icon(
        onPressed: _busy ? null : _alarmOnly,
        icon: const Icon(Icons.alarm),
        label: const Text('Yalnızca alarm bildirimleri'),
      ),
      KeyedSubtree(
        key: ValueKey(_revision),
        child: const Column(
          children: [
            ContentNotificationSettings(),
            IncomingNotificationSettings(),
          ],
        ),
      ),
    ],
  );
}
