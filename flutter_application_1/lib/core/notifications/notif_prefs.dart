import 'package:flutter/material.dart';
import 'notification_permission.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> editChatNotifications(BuildContext context) async {
  var enabled = await chatNotificationsEnabled();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Telefon bildirimleri'),
              subtitle: const Text(
                'Sohbet içindeki +N rozeti bu ayardan bağımsızdır.',
              ),
              value: enabled,
              onChanged: (value) async {
                if (value) {
                  final granted = await FlutterLocalNotificationsPlugin()
                      .resolvePlatformSpecificImplementation<
                        AndroidFlutterLocalNotificationsPlugin
                      >()
                      ?.requestNotificationsPermission();
                  if (granted == false) return;
                }
                await setChatNotifications(value);
                if (ctx.mounted) update(() => enabled = value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_notifications_outlined),
              title: const Text('Sohbet bildirim yazısını değiştir'),
              onTap: () async {
                Navigator.pop(ctx);
                await editNotifText(context, kNotifChats);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

const kChatNotificationsKey = 'chat_notifications_enabled';
Future<void> migrateNotificationPreferences() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final legacy = p.getBool(kPushBarKey) ?? false;
  final chats = p.getBool(kChatNotificationsKey) ?? legacy;
  for (final kind in [
    kNotifChats,
    ...kAllContentNotifs,
    kNotifNews,
    kNotifUpdates,
    kNotifStorage,
  ]) {
    final key = 'content_notification_${kind.collection}';
    if (!p.containsKey(key)) {
      await p.setBool(
        key,
        (kind == kNotifChats || kind == kNotifLetters) ? chats : legacy,
      );
    }
  }
}

Future<bool> chatNotificationsEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getBool('content_notification_chats') ??
      prefs.getBool(kChatNotificationsKey) ??
      prefs.getBool(kPushBarKey) ??
      false;
}

Future<bool> contentNotificationEnabled(ContentNotif kind) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getBool('content_notification_${kind.collection}') ??
      ((kind == kNotifLetters || kind == kNotifChats)
          ? await chatNotificationsEnabled()
          : await pushBarEnabled());
}

const kNotifNews = ContentNotif(
  collection: 'news',
  id: 903,
  seenKey: 'seen_news',
  templateKey: 'tmpl_news',
  label: 'Haberler',
  defaultText: 'Yeni haberler eklendi.',
);

class ContentNotificationSettings extends StatelessWidget {
  const ContentNotificationSettings({super.key, this.newsOnly = false});
  final bool newsOnly;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final kind
          in newsOnly
              ? [kNotifNews]
              : [
                  kNotifChats,
                  ...kAllContentNotifs,
                  kNotifUpdates,
                  kNotifStorage,
                ])
        FeatureNotificationSwitch(kind: kind),
    ],
  );
}

class FeatureNotificationSwitch extends StatefulWidget {
  const FeatureNotificationSwitch({super.key, required this.kind});
  final ContentNotif kind;
  @override
  State<FeatureNotificationSwitch> createState() =>
      _FeatureNotificationSwitchState();
}

class _FeatureNotificationSwitchState extends State<FeatureNotificationSwitch> {
  bool? _enabled;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    contentNotificationEnabled(widget.kind).then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(widget.kind.label),
    subtitle: Text(
      widget.kind == kNotifNews
          ? 'Yeni haberleri uygulama fark ettiğinde haber verir.'
          : widget.kind == kNotifUpdates
          ? 'Yeni uygulama sürümü için telefon bildirimi.'
          : widget.kind == kNotifStorage
          ? 'Depolama dolmaya yaklaştığında haber verir.'
          : '${widget.kind.label} için yeni içerik geldiğinde telefon bildirimi. Kapalıysa yalnızca uygulama içinde görürsün.',
    ),
    value: _enabled ?? false,
    onChanged: _enabled == null || _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              if (value) {
                if (!await ensureNotificationPermission(context)) return;
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(
                'content_notification_${widget.kind.collection}',
                value,
              );
              if (widget.kind == kNotifChats) {
                await prefs.setBool(kChatNotificationsKey, value);
              }
              if (mounted) setState(() => _enabled = value);
              // Platform cleanup must never undo a successfully saved choice.
              try {
                if (!value) {
                  await FlutterLocalNotificationsPlugin()
                      .cancel(widget.kind.id)
                      .timeout(const Duration(seconds: 3));
                }
                if (widget.kind == kNotifUpdates) {
                  if (value) {
                    await FirebaseMessaging.instance
                        .subscribeToTopic('updates')
                        .timeout(const Duration(seconds: 3));
                  } else {
                    await FirebaseMessaging.instance
                        .unsubscribeFromTopic('updates')
                        .timeout(const Duration(seconds: 3));
                  }
                }
              } catch (_) {
                /* The saved preference still gates delivery. */
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ayar kaydedilemedi. Yeniden dene.'),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}

Future<void> setChatNotifications(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kChatNotificationsKey, value);
  await prefs.setBool('content_notification_chats', value);
  if (!value) {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancel(kNotifChats.id);
  }
}

class ChatNotificationsSwitch extends StatefulWidget {
  const ChatNotificationsSwitch({super.key});
  @override
  State<ChatNotificationsSwitch> createState() =>
      _ChatNotificationsSwitchState();
}

class _ChatNotificationsSwitchState extends State<ChatNotificationsSwitch> {
  bool? _enabled;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    chatNotificationsEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Sohbet bildirimleri'),
    subtitle: const Text(
      'Kapalıyken sohbet yenilikleri yalnızca uygulamada görünür. Uyandırma izinleri ayrıdır.',
    ),
    value: _enabled ?? false,
    onChanged: _enabled == null || _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              if (value) {
                final granted = await FlutterLocalNotificationsPlugin()
                    .resolvePlatformSpecificImplementation<
                      AndroidFlutterLocalNotificationsPlugin
                    >()
                    ?.requestNotificationsPermission();
                if (granted == false) return;
              }
              await setChatNotifications(value);
              if (mounted) setState(() => _enabled = value);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Bildirim ayarı kaydedilemedi. Yeniden dene.',
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

/// Gizli bölümdeki her içerik türünün KENDİ bildirimi vardır: kendi sayacı,
/// kendi bildirim kimliği ve kendi (kullanıcı tarafından değiştirilebilen)
/// yazısı. Varsayılan yazı özelliğin adıdır (ör. "Sesli Notlar"); gizlilik
/// isteyen kullanıcı her birini kendi sayfasından masum bir metinle değiştirebilir.
class ContentNotif {
  /// Firestore alt koleksiyonu ('questions' özel: answers haritası).
  final String collection;

  /// Bildirim kimliği (her tür ayrı ki üst üste binmesin).
  final int id;

  /// "Şu ana kadar görülen" sayacının anahtarı.
  final String seenKey;

  /// Kullanıcının yazdığı metnin anahtarı.
  final String templateKey;

  /// Ayar ekranında görünen ad.
  final String label;

  /// Kullanıcı bir şey yazmadıysa kullanılacak masum metin.
  final String defaultText;

  const ContentNotif({
    required this.collection,
    required this.id,
    required this.seenKey,
    required this.templateKey,
    required this.label,
    required this.defaultText,
  });
}

const ContentNotif kNotifLetters = ContentNotif(
  collection: 'letters',
  id: 891,
  seenKey: 'seen_letters',
  // Eski sürümdeki anahtar — kullanıcının yazdığı metin korunsun.
  templateKey: 'notif_template_incoming',
  label: 'Mektuplar',
  defaultText: 'Mektuplar',
);

const ContentNotif kNotifVoice = ContentNotif(
  collection: 'voicenotes',
  id: 892,
  seenKey: 'seen_voicenotes',
  templateKey: 'tmpl_voicenotes',
  label: 'Sesli Notlar',
  defaultText: 'Sesli Notlar',
);

const ContentNotif kNotifTimeline = ContentNotif(
  collection: 'timeline',
  id: 893,
  seenKey: 'seen_timeline',
  templateKey: 'tmpl_timeline',
  label: 'Anılar',
  defaultText: 'Anılar',
);

const ContentNotif kNotifWishes = ContentNotif(
  collection: 'wishes',
  id: 894,
  seenKey: 'seen_wishes',
  templateKey: 'tmpl_wishes',
  label: 'Ortak Dilekler',
  defaultText: 'Ortak Dilekler',
);

const ContentNotif kNotifHidden = ContentNotif(
  collection: 'hiddenimages',
  id: 895,
  seenKey: 'seen_hiddenimages',
  templateKey: 'tmpl_hiddenimages',
  label: 'Gizli Resimler',
  defaultText: 'Gizli Resimler',
);

const ContentNotif kNotifNotes = ContentNotif(
  collection: 'notes',
  id: 896,
  seenKey: 'seen_notes',
  templateKey: 'tmpl_notes',
  label: 'Özel Günler & Notlar',
  defaultText: 'Özel Günler & Notlar',
);

const ContentNotif kNotifQuestions = ContentNotif(
  collection: 'questions',
  id: 897,
  seenKey: 'seen_questions',
  templateKey: 'tmpl_questions',
  label: 'Günün Sorusu',
  defaultText: 'Günün Sorusu',
);

const ContentNotif kNotifChats = ContentNotif(
  collection: 'chats',
  id: 898,
  seenKey: 'seen_chat_messages',
  templateKey: 'tmpl_chat_messages',
  label: 'Sohbetler',
  defaultText: 'Yeni bir güncelleme mevcut.',
);

/// Kontrol edilen tüm türler.
const List<ContentNotif> kAllContentNotifs = [
  kNotifLetters,
  kNotifVoice,
  kNotifTimeline,
  kNotifWishes,
  kNotifHidden,
  kNotifNotes,
  kNotifQuestions,
];

/// Telefonun bildirim çubuğuna bildirim gönderilsin mi.
/// VARSAYILAN: KAPALI. Yeni içerik uygulamanın içinde kırmızı "+N" rozetiyle
/// gösterilir; telefonda hiçbir iz bırakmaz. İsteyen bu anahtarı açabilir.
const String kPushBarKey = 'push_bar_enabled';

Future<bool> pushBarEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  // Arka plan görevi ayrı önbellek tutar; diskten tazele.
  try {
    await prefs.reload();
  } catch (_) {}
  return prefs.getBool(kPushBarKey) ?? false;
}

/// Bu tür için gösterilecek metni döndürür (kullanıcı yazdıysa onu).
Future<String> notifText(ContentNotif n) async {
  final prefs = await SharedPreferences.getInstance();
  final t = (prefs.getString(n.templateKey) ?? '').trim();
  return t.isEmpty ? n.defaultText : t;
}

/// Bu türün bildirim yazısını düzenleme penceresi. Her özellik kendi
/// sayfasından çağırır.
Future<void> editNotifText(BuildContext context, ContentNotif n) async {
  final prefs = await SharedPreferences.getInstance();
  final mevcut = (prefs.getString(n.templateKey) ?? '').trim();
  final c = TextEditingController(
    text: mevcut.isEmpty ? n.defaultText : mevcut,
  );
  if (!context.mounted) return;

  final kaydet = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("${n.label} bildirimi"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Bu bölüme yeni bir şey eklenince telefonda çıkacak yazı. "
            "Gizli kalsın istersen masum bir metin yazabilirsin.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: n.defaultText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("İptal"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("Kaydet"),
        ),
      ],
    ),
  );

  if (kaydet == true) {
    final yeni = c.text.trim();
    await prefs.setString(n.templateKey, yeni.isEmpty ? n.defaultText : yeni);
  }
}

const kNotifUpdates = ContentNotif(
  collection: 'app_updates',
  id: 890,
  seenKey: 'seen_app_updates',
  templateKey: 'tmpl_app_updates',
  label: 'Uygulama güncellemeleri',
  defaultText: 'Yeni bir güncelleme mevcut.',
);
const kNotifStorage = ContentNotif(
  collection: 'storage',
  id: 902,
  seenKey: 'seen_storage',
  templateKey: 'tmpl_storage',
  label: 'Depolama uyarıları',
  defaultText: 'Depolama dolmaya yaklaşıyor.',
);
