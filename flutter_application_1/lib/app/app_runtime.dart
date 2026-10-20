import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../features/pair/couple_service.dart';
import '../core/notifications/notif_prefs.dart';
import '../features/updates/update_service.dart';
import '../features/pair/badge_service.dart';
import '../features/location/location_share.dart';
import '../features/media/chat_media.dart';
import '../features/chat/chat_unread.dart';
import '../features/wakeup/wakeup_service.dart';
import '../features/storage/storage_monitor.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// İlişkinin başlangıç tarihi. Hem uygulama hem de arka plan görevi buraya bakar.
final DateTime kBaslangicTarihi = DateTime.now();

/// Arka plan görevinin adı — gün değişince bildirimi kendi kendine tazeler.
const String kNotifTaskName = 'refresh_counter_notification';
const int kNotifId = 888;

/// Gerçek mod bildirim yazısının varsayılanı. Kullanıcı değiştirebilir.
/// "{gun}" yazdığı yere güncel gün sayısı gelir.
const String kDefaultNotifTemplate = '{gun} gün geçti.';

/// Gizleme modu bildiriminin varsayılanı. Masum görünsün ama sayı içersin.
const String kDefaultDisguisedTemplate =
    'Son güncelleme {gun} gün önce yapıldı.';

/// Yeni mektup gelince gösterilen (gizli) bildirimin varsayılanı. Kullanıcı
/// değiştirebilir. Masum görünmeli — sıradan bir güncelleme gibi.
const String kDefaultIncomingTemplate = 'Yeni bir güncelleme mevcut.';
const int kIncomingNotifId = 889;

/// Arka planda yeni sürüm bulununca gösterilen güncelleme bildiriminin ID'si.
const int kUpdateNotifId = 890;

/// Karşı taraftan yeni mektup gelip gelmediğini kontrol eder; geldiyse gizli
/// bir bildirim gösterir. Hem uygulama açılışında hem arka plan görevinde
/// çalışır (uygulama kapalıyken bile ~saatlik kontrol).
Future<void> checkIncomingContent() async {
  final prefs = await SharedPreferences.getInstance();
  // Arka plan görevi ile uygulama ayrı önbellek tutar; diskten tazele ki
  // aynı bildirim tekrar tekrar gösterilmesin.
  try {
    await prefs.reload();
  } catch (_) {}

  try {
    if (await hasNewChatMessages() && await chatNotificationsEnabled()) {
      await flutterLocalNotificationsPlugin.show(
        kNotifChats.id,
        'Güncelleme',
        await notifText(kNotifChats),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'updates',
            'Güncellemeler',
            importance: Importance.defaultImportance,
          ),
        ),
      );
    }
  } catch (_) {}
  final cid = prefs.getString('couple_id');
  if (cid == null) return; // eşleşme yoksa kontrol edilecek bir şey yok

  final myUid = prefs.getString('my_uid');
  // Kendi kimliğimizi bilmiyorsak "eşinden geldi" diyemeyiz — yoksa kendi
  // eklediklerimiz de eşten gelmiş sayılıp yanlış bildirim çıkar.
  if (myUid == null || myUid.isEmpty) return;

  try {
    // Eşin eklediklerinin sayısı. Sayım BadgeService'te tek yerde yapılır:
    // belgeler indirilmez, sunucuya yalnızca adet sorulur.
    //
    // Burada eskiden her koleksiyon `.get()` ile TAMAMEN indiriliyordu.
    // Resim ve sesler Firestore'da base64 durduğu için bu, her açılışta ve
    // her saatlik arka plan görevinde onlarca MB indirip belleğe açmak
    // demekti; çöp toplayıcı sürekli çalışıp arayüzü kilitliyordu.
    final counts = await BadgeService.partnerCounts();
    if (counts.isEmpty) return; // eş yok / eşleşme yok / internet yok

    const AndroidNotificationDetails incomingDetails =
        AndroidNotificationDetails(
          'updates',
          'Güncellemeler',
          channelDescription: 'Uygulama güncelleme bildirimi',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
        );

    // Bildirim çubuğuna yazma izni. Kapalıysa sayaçlar yine güncellenir
    // (gizli bölümdeki kırmızı rozet ayrı sayaç kullanır) ama telefonda
    // hiçbir bildirim görünmez.

    // HER TÜR AYRI: kendi sayacı, kendi bildirimi, kendi yazısı.
    for (final kind in kAllContentNotifs) {
      final int? partnerCount = counts[kind.collection];
      if (partnerCount == null) continue;

      final int? seen = prefs.getInt(kind.seenKey);
      if (seen == null) {
        // İlk kez: mevcut sayıyı temel al, bildirim gösterme.
        await prefs.setInt(kind.seenKey, partnerCount);
        continue;
      }
      final allowed = await contentNotificationEnabled(kind);
      if (allowed && partnerCount > seen) {
        await flutterLocalNotificationsPlugin.show(
          kind.id,
          'Güncelleme',
          await notifText(kind),
          const NotificationDetails(android: incomingDetails),
        );
      }
      await prefs.setInt(kind.seenKey, partnerCount);
    }
  } catch (_) {
    // İnternet yok / hata — sessizce geç.
  }
}

/// Arka planda yeni sürüm var mı kontrol eder; varsa (ve o sürüm için daha önce
/// bildirilmediyse) masum bir güncelleme bildirimi gösterir. Uygulama kapalıyken
/// bile çalışır — kullanıcının güncellemeyi görmek için uygulamayı açması gerekmez.
Future<void> checkUpdateAndNotify() async {
  try {
    // Bildirim çubuğu kapalıysa buradan da hiçbir şey gönderilmez.
    if (!await contentNotificationEnabled(kNotifUpdates)) return;
    final info = await UpdateService.checkForUpdate();
    if (info == null) return; // güncel — bildirilecek bir şey yok

    final prefs = await SharedPreferences.getInstance();
    final int notified = prefs.getInt('notified_update_code') ?? 0;
    if (info.code <= notified) {
      return; // bu sürüm için zaten bildirildi (spam yok)
    }

    const AndroidNotificationDetails details = AndroidNotificationDetails(
      'updates',
      'Güncellemeler',
      channelDescription: 'Uygulama güncelleme bildirimi',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    await flutterLocalNotificationsPlugin.show(
      kUpdateNotifId,
      'Güncelleme',
      'Yeni bir güncelleme mevcut. Uygulamayı güncelleyin.',
      const NotificationDetails(android: details),
    );
    await prefs.setInt('notified_update_code', info.code);
  } catch (_) {
    // İnternet yok / hata — sessizce geç.
  }
}

/// Notların/özel günlerin başına konabilecek simgeler.
const List<String> kNotEmojileri = [
  '🖤',
  '💜',
  '❤️',
  '💍',
  '🌹',
  '🎂',
  '🎁',
  '✈️',
  '🎵',
  '⭐',
  '📌',
  '🔒',
];

const List<String> kAylar = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Depolama için: 2026-03-17
String formatIsoDate(DateTime d) =>
    "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

/// Ekranda göstermek için: 17 Mart 2026
String formatDisplayDate(DateTime d) =>
    "${d.day} ${kAylar[d.month - 1]} ${d.year}";

/// Bildirim eklentisini başlatır (hem ön planda hem arka plan izolatında çağrılır).
Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_neural');
  const InitializationSettings settings = InitializationSettings(
    android: androidInit,
  );
  await flutterLocalNotificationsPlugin.initialize(settings);
  await migrateNotificationPreferences();
}

/// Ayarları SharedPreferences'ten okuyup güncel gün sayısıyla kalıcı bildirimi
/// gösterir. Kapalıysa bildirimi kaldırır. Ön plan ve arka plan tarafından
/// ortak kullanılır ki metin tek bir yerde üretilsin.
Future<void> showCounterNotification() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final bool active = prefs.getBool('notif_active') ?? false;
  final bool disguised = prefs.getBool('notif_disguised') ?? false;

  if (!active) {
    await flutterLocalNotificationsPlugin.cancel(kNotifId);
    return;
  }

  final start = DateTime.tryParse(prefs.getString('counter_start') ?? '');
  if (start == null) {
    await flutterLocalNotificationsPlugin.cancel(kNotifId);
    return;
  }
  final now = DateTime.now();
  final int gun = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  final String tmpl = (prefs.getString('notif_template') ?? '').trim();
  final String realBody = (tmpl.isEmpty ? kDefaultNotifTemplate : tmpl)
      .replaceAll('{gun}', '$gun');
  final String dTmpl = (prefs.getString('notif_template_disguised') ?? '')
      .trim();
  final String disguisedBody =
      (dTmpl.isEmpty ? kDefaultDisguisedTemplate : dTmpl).replaceAll(
        '{gun}',
        '$gun',
      );
  final String title = disguised ? "Sistem Güncellemesi" : "Sayaç";
  final String body = disguised ? disguisedBody : realBody;

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'system_status',
    'Sistem Durumu',
    channelDescription: 'Sistem bildirimi',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
  );
  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(kNotifId, title, body, details);
}

/// Arka plan izolatının giriş noktası. WorkManager periyodik olarak burayı
/// çağırır; uygulama kapalı olsa bile bildirimi güncel tutar.
@pragma('vm:entry-point')
void runBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await initializeLocalNotifications();
    await showCounterNotification();
    // Uygulama kapalıyken bile yeni mektup + güncelleme kontrolü.
    try {
      await CoupleService.ensureReady();
      await LocationShares.cleanupExpired();
      await ChatMedia.cleanupExpired().catchError((Object _) {});
      await checkIncomingContent();
      await checkUpdateAndNotify();
    } catch (_) {}
    return true;
  });
}

/// Firebase, izinler ve arka plan görevi — UI açıldıktan sonra, bloklamadan.
Future<void> initializeBackground(void Function() dispatcher) async {
  try {
    // Oturumu tek bir yerden aç: CoupleService de aynı future'ı bekler.
    // İki ayrı signInAnonymously() çağrısı yarışırsa iki farklı anonim
    // hesap açılır ve çift "üçüncü bir üye" kazanır.
    await CoupleService.ensureReady();
    unawaited(LocationShares.cleanupExpired().catchError((Object _) {}));
    unawaited(ChatMedia.cleanupExpired().catchError((Object _) {}));
    unawaited(_checkStorageWarning());
    final u = CoupleService.uid;
    if (u != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('my_uid', u);
    }
    await checkIncomingContent();
  } catch (_) {}

  try {
    await Workmanager().initialize(dispatcher);
    await Workmanager().registerPeriodicTask(
      'counter-update',
      kNotifTaskName,
      frequency: const Duration(hours: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {}

  // FCM: yeni sürüm yayınlanınca anlık "güncelleme var" push'u için. Herkes
  // "updates" konusuna abone olur; yayınlarken o konuya tek push gönderilir.
  await _initFcm();
}

Future<void> _checkStorageWarning() async {
  try {
    final report = await StorageMonitor.check();
    if (report?['warning'] != true ||
        report?['stale'] == true ||
        !await contentNotificationEnabled(kNotifStorage)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (prefs.getString('storage_warning_day') == day) return;
    await flutterLocalNotificationsPlugin.show(
      902,
      'Depolama uyarısı',
      'Uygulamanın ücretsiz depolama alanı dolmaya yaklaşıyor.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'storage_capacity',
          'Depolama uyarıları',
          importance: Importance.defaultImportance,
        ),
      ),
    );
    await prefs.setString('storage_warning_day', day);
  } catch (_) {}
}

/// Firebase Cloud Messaging kurulumu — anlık güncelleme bildirimleri için.
Future<void> _initFcm() async {
  try {
    final messaging = FirebaseMessaging.instance;
    unawaited(WakeupService.restoreRegistration());
    if (await contentNotificationEnabled(kNotifUpdates)) {
      await messaging.subscribeToTopic('updates');
    } else {
      await messaging.unsubscribeFromTopic('updates');
    }
    // Uygulama ön plandayken push gelirse Android otomatik göstermez → elle göster.
    FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
      final n = m.notification;
      if (n == null) return;
      // Kullanıcı bildirim çubuğunu kapattıysa push de gösterilmez.
      if (!await contentNotificationEnabled(kNotifUpdates)) return;
      const AndroidNotificationDetails details = AndroidNotificationDetails(
        'updates',
        'Güncellemeler',
        channelDescription: 'Uygulama güncelleme bildirimi',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
      );
      flutterLocalNotificationsPlugin.show(
        kUpdateNotifId,
        n.title ?? 'Güncelleme',
        n.body ?? 'Yeni bir güncelleme mevcut.',
        const NotificationDetails(android: details),
      );
    });
  } catch (_) {
    // İzin yok / hata — sessizce geç.
  }
}
