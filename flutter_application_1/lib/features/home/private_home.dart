import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../contacts/contacts_screen.dart';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../pair/couple_service.dart';
import '../../core/notifications/notif_prefs.dart';
import '../media/image_util.dart';
import '../counter/counter_page.dart';
import '../../core/theme/chat_theme.dart';
import '../../core/security/secure_screen.dart';
import '../questions/question_screen.dart';
import '../timeline/timeline_screen.dart';
import '../../core/theme/app_theme.dart';
import '../voice_notes/voice_notes_screen.dart';
import '../wishes/wishes_screen.dart';
import '../pair/badge_service.dart';
import '../chat/chat_unread.dart';
import '../settings/app_settings_screen.dart';
import '../study/course_screen.dart';

import '../../app/app_runtime.dart';
import '../media/full_image_screen.dart';

class CounterScreen extends StatefulWidget {
  final DateTime startDate;
  final bool isNotifActive;
  final bool isDisguised;
  final Function(bool active, bool disguised) onSettingsChanged;
  final VoidCallback onBack;

  const CounterScreen({
    super.key,
    required this.startDate,
    required this.isNotifActive,
    required this.isDisguised,
    required this.onSettingsChanged,
    required this.onBack,
  });

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  /// ESKİ, bu telefonda kalmış notlar (eşleşince otomatik paylaşıma taşınır).
  /// Her not: { "text": String, "emoji": String, "date": String? ("yyyy-MM-dd") }
  List<Map<String, dynamic>> _notes = [];

  /// ESKİ, bu telefonda kalmış gizli resimler (eşleşince otomatik paylaşılır).
  List<String> _hiddenImages = [];

  // Eşleşme — gizli bölümdeki her şey ikisinde de görünsün diye.
  String? _coupleId;
  String? _secret;
  Stream<List<HiddenImage>>? _imagesStream;
  Stream<List<CoupleNote>>? _notesStream;
  bool get _paired => _coupleId != null && _secret != null;

  late bool _notifActive;
  late bool _disguised;
  String _notifTemplate = kDefaultNotifTemplate;
  String _notifTemplateDisguised = kDefaultDisguisedTemplate;

  /// Bildirim çubuğuna bildirim gönderilsin mi (varsayılan kapalı).

  /// Koleksiyon adı → görülmemiş yeni içerik sayısı. Kırmızı "+N" rozetleri.
  Map<String, int> _rozetler = {};

  /// Son sayım. "Görüldü" işaretlerken tekrar ağa çıkmamak için saklanır.
  Map<String, int> _sayimlar = {};

  @override
  void initState() {
    super.initState();
    _notifActive = widget.isNotifActive;
    _disguised = widget.isDisguised;
    SecureScreen.enable(); // gizli bölümde ekran görüntüsü engellensin
    _load();
    _rozetleriYenile();
  }

  /// Rozet sayaçlarını tazeler. Bildirim çubuğuna hiçbir şey göndermez.
  /// Sayım tek seferde alınır ve saklanır; "görüldü" işaretleri bunu kullanır.
  Future<void> _rozetleriYenile() async {
    final sayim = await BadgeService.partnerCounts();
    if (sayim.isEmpty) return;
    final r = await BadgeService.unseenFrom(sayim);
    if (mounted) {
      setState(() {
        _sayimlar = sayim;
        _rozetler = r;
      });
    }
  }

  int _rozet(ContentNotif n) => _rozetler[n.collection] ?? 0;

  /// İndirme izni akışı: gelen istekleri ve onaylanan kendi isteklerimi dinler.
  StreamSubscription? _reqSub;
  StreamSubscription? _approvedSub;
  bool _askingDownload = false;

  @override
  void dispose() {
    _reqSub?.cancel();
    _approvedSub?.cancel();
    // Bu ekranda doğrudan listelenen bölümler (gizli resimler, notlar)
    // görülmüş sayılır — rozetleri bir sonraki girişte temiz olsun.
    BadgeService.markSeenWith(_sayimlar, const [kNotifHidden, kNotifNotes]);
    SecureScreen.disable(); // Android'de uygulama genelindeki koruma devam eder
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('my_notes_v2');

    List<Map<String, dynamic>> notes = [];
    if (raw != null && raw.isNotEmpty) {
      notes = (jsonDecode(raw) as List)
          .map(
            (e) => <String, dynamic>{
              'text': (e['text'] ?? '').toString(),
              'emoji': (e['emoji'] ?? '📌').toString(),
              'date': e['date'], // null olabilir
            },
          )
          .toList();
    } else {
      // Eski surumden gecis: duz metin notlari yeni bicime tasi, kaybolmasin.
      final List<String> eski = prefs.getStringList('my_notes') ?? [];
      notes = eski
          .map((t) => <String, dynamic>{'text': t, 'emoji': '📌', 'date': null})
          .toList();
      if (notes.isNotEmpty) {
        await prefs.setString('my_notes_v2', jsonEncode(notes));
      }
    }

    final String tmpl = (prefs.getString('notif_template') ?? '').trim();
    final String dTmpl = (prefs.getString('notif_template_disguised') ?? '')
        .trim();

    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    if (!mounted) return;

    setState(() {
      _notes = notes;
      _hiddenImages = prefs.getStringList('hidden_images') ?? [];
      if (_coupleId != cid || _secret != sec) {
        _imagesStream = cid == null || sec == null
            ? null
            : CoupleService.hiddenImagesStream(cid, sec);
        _notesStream = cid == null || sec == null
            ? null
            : CoupleService.notesStream(cid, sec);
      }
      _coupleId = cid;
      _secret = sec;
      _notifTemplate = tmpl.isEmpty ? kDefaultNotifTemplate : tmpl;
      _notifTemplateDisguised = dTmpl.isEmpty
          ? kDefaultDisguisedTemplate
          : dTmpl;
    });

    // Eşleşme varsa bu telefonda kalmış eski içerikleri sessizce paylaşıma taşı.
    if (_paired) {
      unawaited(_prepareSecretLogin());
      unawaited(_autoShareLegacy());
      _startDownloadWatchers();
    }
  }

  Future<void> _prepareSecretLogin() async {
    try {
      await CoupleService.enableSecretLogin();
      final prefs = await SharedPreferences.getInstance();
      if (mounted && prefs.getString('secret_login_ready') != _coupleId) {
        await prefs.setString('secret_login_ready', _coupleId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gizli kelimeyle yeniden giriş hazır. Yeniden kurulumda davet koduna ihtiyacın yok.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gizli kelimeyle yeniden giriş hazırlanamadı: ${error.toString().replaceFirst("Exception: ", "")}. Bu bölüme tekrar girerek yeniden deneyebilirsin.',
          ),
        ),
      );
    }
  }

  /// Eski yerel gizli resimleri ve notları paylaşıma yükler. Kullanıcı hiçbir
  /// şey yapmasın diye arka planda, en iyi çabayla. Sığmayan resim yerelde kalır.
  Future<void> _autoShareLegacy() async {
    // Gizli resimler
    for (final path in List<String>.from(_hiddenImages)) {
      try {
        final f = File(path);
        if (!await f.exists()) {
          await _dropLegacyHidden(path);
          continue;
        }
        final bytes = await f.readAsBytes();
        try {
          await CoupleService.addHiddenImage(bytes);
        } catch (e) {
          if (!e.toString().contains('büyük')) rethrow;
          await CoupleService.addHiddenImage(await _downscale(bytes));
        }
        await _dropLegacyHidden(path);
        try {
          await f.delete();
        } catch (_) {}
      } catch (_) {
        // Sığmadı/hata — yerelde kalsın.
      }
    }
    // Notlar / özel günler
    for (final n in List<Map<String, dynamic>>.from(_notes)) {
      try {
        await CoupleService.addNote(
          text: (n['text'] ?? '').toString(),
          emoji: (n['emoji'] ?? '📌').toString(),
          date: n['date'] as String?,
        );
        if (!mounted) return;
        setState(() => _notes.remove(n));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('my_notes_v2', jsonEncode(_notes));
      } catch (_) {}
    }
  }

  Future<void> _dropLegacyHidden(String path) async {
    if (!mounted) return;
    setState(() => _hiddenImages.remove(path));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_images', _hiddenImages);
  }

  /// Sığıyorsa orijinali korur; sığmıyorsa sığacak en iyi kaliteye indirir.
  Future<Uint8List> _downscale(Uint8List src) => compressToFit(src);

  /// Bildirim yazısını kullanıcı düzenler. [disguised] hangi modun yazısı
  /// olduğunu belirler. "{gun}" -> gün sayısı.
  Future<void> _editNotifText(bool disguised) async {
    final mevcut = disguised ? _notifTemplateDisguised : _notifTemplate;
    final varsayilan = disguised
        ? kDefaultDisguisedTemplate
        : kDefaultNotifTemplate;
    final anahtar = disguised ? 'notif_template_disguised' : 'notif_template';

    final c = TextEditingController(text: mevcut);
    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(disguised ? "Gizleme Bildirimi" : "Bildirim Yazısı"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              disguised
                  ? "Gizleme modunda görünecek masum yazı. {gun} yazdığın "
                        "yere gün sayısı gelir."
                  : "Gerçek modda üst çubukta görünecek yazı. {gun} yazdığın "
                        "yere gün sayısı gelir.",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: disguised
                    ? "örn: Yedekleme {gun} gün önce yapıldı."
                    : "örn: {gun} gündür seninleyim 💜",
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
      final yeni = c.text.trim().isEmpty ? varsayilan : c.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(anahtar, yeni);
      setState(() {
        if (disguised) {
          _notifTemplateDisguised = yeni;
        } else {
          _notifTemplate = yeni;
        }
      });
      // Ayarları parent'a bildir → bildirim yeni yazıyla tazelenir.
      widget.onSettingsChanged(_notifActive, _disguised);
    }
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_notes_v2', jsonEncode(_notes));
  }

  Future<void> _deleteNote(Map<String, dynamic> n) async {
    setState(() => _notes.remove(n));
    await _saveNotes();
  }

  // Gizli menüde bir özelliği açan kart.
  Widget _ozellikKart(
    String emoji,
    String baslik,
    Widget ekran, [
    ContentNotif? notif,
  ]) {
    final int yeni = notif == null ? 0 : _rozet(notif);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ekran));
        // Bölüm görüldü → rozeti sıfırla (elimizdeki sayımla, ağa çıkmadan)
        // ve ardından kalanları tek sorguda tazele.
        if (notif != null) await BadgeService.markSeenWith(_sayimlar, [notif]);
        await _rozetleriYenile();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                baslik,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (ekran is ContactsScreen)
              ChatTotalBadge(baseCount: yeni)
            else
              YeniRozet(yeni),
          ],
        ),
      ),
    );
  }

  /// Tarihi olan kayitlar = ozel gunler (tarihe gore sirali).
  List<Map<String, dynamic>> get _ozelGunler {
    final list = _notes.where((n) => n['date'] != null).toList();
    list.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return list;
  }

  /// Tarihi olmayanlar = sirdan notlar.
  List<Map<String, dynamic>> get _duzNotlar =>
      _notes.where((n) => n['date'] == null).toList();

  /// Özel gün kartı — hem paylaşımlı hem eski yerel kayıtlar bunu kullanır.
  Widget _ozelGunKarti({
    required String emoji,
    required String text,
    required String dateIso,
    required VoidCallback onDelete,
  }) {
    final DateTime d = DateTime.parse(dateIso);
    final DateTime bugun = DateTime.now();
    final int gun = DateTime(
      bugun.year,
      bugun.month,
      bugun.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;

    final String sayac = gun == 0
        ? "Bugün! 🎉"
        : gun > 0
        ? "$gun gündür"
        : "${-gun} gün kaldı";

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 28)),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text("${formatDisplayDate(d)}  ·  $sayac"),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }

  /// Düz not satırı — hem paylaşımlı hem eski yerel kayıtlar bunu kullanır.
  Widget _duzNotSatiri({
    required String emoji,
    required String text,
    required VoidCallback onDelete,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
      title: Text(text),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }

  Widget _bosYazi(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: const TextStyle(color: Colors.grey)),
  );

  // ── Emoji tepki ──
  /// Gizli resme emoji tepki bırakır. Kullanıcı klavyeden istediği emojiyi seçer.
  Future<void> _reactToHidden(HiddenImage h) async {
    final c = TextEditingController(text: h.myReaction ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tepki bırak"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Klavyeden istediğin emojiyi seçebilirsin.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30),
              maxLength: 4,
              decoration: const InputDecoration(
                hintText: "❤️",
                counterText: "",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['❤️', '😍', '🔥', '😂', '🥹', '👏']
                  .map(
                    (e) => GestureDetector(
                      onTap: () => Navigator.pop(ctx, e),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text("Kaldır"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text("Tamam"),
          ),
        ],
      ),
    );
    if (res == null) return;
    await CoupleService.setHiddenImageReaction(h.id, res.isEmpty ? null : res);
  }

  // ── İndirme (sahibinden izinli) ──
  /// Kendi fotoğrafımsa doğrudan kaydeder; eşinse ondan izin ister.
  Future<void> _askDownload({
    required String kind,
    required String itemId,
    required String ownerUid,
    required bool mine,
    Uint8List? bytes,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (mine) {
      await _saveToGallery(bytes);
      return;
    }
    try {
      await CoupleService.requestDownload(
        kind: kind,
        itemId: itemId,
        ownerUid: ownerUid,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "İzin istendi — eşin onaylayınca galerine kaydedilecek.",
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _saveToGallery(Uint8List? bytes) async {
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(bytes);
      messenger.showSnackBar(
        const SnackBar(content: Text("Galeriye kaydedildi ✅")),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Kaydedilemedi: $e")));
    }
  }

  /// Sahibi ben olan istekleri dinler (onay sorar) ve onaylanan kendi
  /// isteklerimi otomatik galeriye kaydeder.
  void _startDownloadWatchers() {
    final cid = _coupleId;
    if (cid == null) return;

    _reqSub?.cancel();
    _reqSub = CoupleService.incomingDownloadRequests(cid).listen((list) async {
      if (list.isEmpty || _askingDownload || !mounted) return;
      _askingDownload = true;
      final r = list.first;

      // HANGİ içerik için izin istendiğini göster — körlemesine onay olmasın.
      final Uint8List? onizleme = r.kind == 'hiddenimage'
          ? await CoupleService.fetchHiddenImageBytes(r.itemId)
          : await CoupleService.fetchTimelineImageBytes(r.itemId);
      final String nereden = r.kind == 'hiddenimage'
          ? 'Gizli Resimler'
          : 'Anılar';
      if (!mounted) {
        _askingDownload = false;
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("İndirme izni"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Eşin şu içeriği indirmek istiyor · $nereden",
                style: const TextStyle(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (onizleme != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    onizleme,
                    height: 200,
                    fit: BoxFit.contain,
                    cacheWidth: kDetailMaxSide,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    "(Önizleme yüklenemedi)",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 12),
              const Text("Kabul ediyor musun?"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Hayır"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Evet"),
            ),
          ],
        ),
      );
      await CoupleService.respondDownload(r.id, ok == true);
      if (ok != true) await CoupleService.clearDownloadRequest(r.id);
      _askingDownload = false;
    });

    _approvedSub?.cancel();
    _approvedSub = CoupleService.myApprovedDownloads(cid).listen((list) async {
      for (final r in list) {
        final bytes = r.kind == 'hiddenimage'
            ? await CoupleService.fetchHiddenImageBytes(r.itemId)
            : await CoupleService.fetchTimelineImageBytes(r.itemId);
        await _saveToGallery(bytes);
        await CoupleService.clearDownloadRequest(r.id);
      }
    });
  }

  // ── Gizli resimler bölümü ──
  Widget _hiddenImagesSection() {
    if (!_paired) {
      if (_hiddenImages.isEmpty) return _bosYazi("Henüz gizli resim yok.");
      return _hiddenStrip([
        for (int i = 0; i < _hiddenImages.length; i++) _legacyHiddenTile(i),
      ]);
    }
    return StreamBuilder<List<HiddenImage>>(
      stream: _imagesStream,
      builder: (context, snap) {
        final shared = snap.data ?? [];
        if (shared.isEmpty && _hiddenImages.isEmpty) {
          return _bosYazi("Henüz gizli resim yok.");
        }
        return _hiddenStrip([
          for (final h in shared) _sharedHiddenTile(h),
          for (int i = 0; i < _hiddenImages.length; i++) _legacyHiddenTile(i),
        ]);
      },
    );
  }

  Widget _hiddenStrip(List<Widget> children) => SizedBox(
    height: 130,
    child: ListView(scrollDirection: Axis.horizontal, children: children),
  );

  Widget _sharedHiddenTile(HiddenImage h) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 120,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: h.image == null
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.lock_outline,
                          color: Colors.grey,
                        ),
                      )
                    : GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullImageScreen(
                              bytes: h.image,
                              onDelete: () =>
                                  CoupleService.deleteHiddenImage(h.id),
                            ),
                          ),
                        ),
                        child: Image.memory(
                          h.image!,
                          fit: BoxFit.contain,
                          cacheWidth: kThumbMaxSide,
                        ),
                      ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: PhotoActionButton(
                icon: Icons.close,
                onTap: () async {
                  if (await _resimSilOnayi()) {
                    await CoupleService.deleteHiddenImage(h.id);
                  }
                },
              ),
            ),
            // Emoji tepkiler — dokununca klavyeden emoji seçilir.
            Positioned(
              left: 4,
              bottom: 4,
              child: GestureDetector(
                onTap: () => _reactToHidden(h),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _tepkiYazisi(h),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
              ),
            ),
            // İndir — kendi fotoğrafım değilse eşten izin ister.
            Positioned(
              right: 4,
              bottom: 4,
              child: GestureDetector(
                onTap: () => _askDownload(
                  kind: 'hiddenimage',
                  itemId: h.id,
                  ownerUid: h.ownerUid,
                  mine: h.fromMe,
                  bytes: h.image,
                ),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.download,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Karttaki tepki rozetinin yazısı: tepkiler varsa onlar, yoksa ekleme ipucu.
  String _tepkiYazisi(HiddenImage h) {
    final list = [
      h.myReaction,
      h.partnerReaction,
    ].where((e) => e != null && e.isNotEmpty).join(' ');
    return list.isEmpty ? '☺+' : list;
  }

  Widget _legacyHiddenTile(int i) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 120,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullImageScreen(
                        imagePath: _hiddenImages[i],
                        onDelete: () => _deleteHiddenImage(i),
                      ),
                    ),
                  ),
                  child: Image.file(
                    File(_hiddenImages[i]),
                    fit: BoxFit.contain,
                    cacheWidth: kThumbMaxSide,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: PhotoActionButton(
                icon: Icons.close,
                onTap: () => _confirmDeleteHidden(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _resimSilOnayi() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Resmi sil"),
        content: const Text("Bu resim kalıcı olarak silinecek. Emin misin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Özel günler & notlar bölümü ──
  Widget _notesSection() {
    if (!_paired) {
      return _notesBody(
        [
          for (final n in _ozelGunler)
            _ozelGunKarti(
              emoji: n['emoji'].toString(),
              text: n['text'].toString(),
              dateIso: n['date'] as String,
              onDelete: () => _deleteNote(n),
            ),
        ],
        [
          for (final n in _duzNotlar)
            _duzNotSatiri(
              emoji: n['emoji'].toString(),
              text: n['text'].toString(),
              onDelete: () => _deleteNote(n),
            ),
        ],
        _notes.isEmpty,
      );
    }
    return StreamBuilder<List<CoupleNote>>(
      stream: _notesStream,
      builder: (context, snap) {
        final all = snap.data ?? [];
        final ozel = all.where((n) => n.date != null).toList()
          ..sort((a, b) => a.date!.compareTo(b.date!));
        final duz = all.where((n) => n.date == null).toList();
        return _notesBody(
          [
            for (final n in ozel)
              _ozelGunKarti(
                emoji: n.emoji,
                text: n.text,
                dateIso: n.date!,
                onDelete: () => CoupleService.deleteNote(n.id),
              ),
            for (final n in _ozelGunler)
              _ozelGunKarti(
                emoji: n['emoji'].toString(),
                text: n['text'].toString(),
                dateIso: n['date'] as String,
                onDelete: () => _deleteNote(n),
              ),
          ],
          [
            for (final n in duz)
              _duzNotSatiri(
                emoji: n.emoji,
                text: n.text,
                onDelete: () => CoupleService.deleteNote(n.id),
              ),
            for (final n in _duzNotlar)
              _duzNotSatiri(
                emoji: n['emoji'].toString(),
                text: n['text'].toString(),
                onDelete: () => _deleteNote(n),
              ),
          ],
          all.isEmpty && _notes.isEmpty,
        );
      },
    );
  }

  Widget _notesBody(List<Widget> ozelGunler, List<Widget> duzNotlar, bool bos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bos) _bosYazi("Henüz kayıt yok. + ile özel gün veya not ekle."),
        if (ozelGunler.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            "Özel Günler",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          ...ozelGunler,
          const SizedBox(height: 10),
        ],
        if (duzNotlar.isNotEmpty) ...[
          const Text(
            "Notlar",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          ...duzNotlar,
        ],
      ],
    );
  }

  Future<void> _addNote() async {
    final c = TextEditingController();
    String emoji = kNotEmojileri.first;
    DateTime? tarih;

    final bool? kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Yeni Kayıt"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: c,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: "Örn: Sevgili olduğumuz gün",
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "SİMGE",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kNotEmojileri.map((e) {
                    final secili = emoji == e;
                    return GestureDetector(
                      onTap: () => setLocal(() => emoji = e),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: secili
                              ? Theme.of(context).colorScheme.outlineVariant
                              : null,
                          border: Border.all(
                            color: secili
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: secili ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  "ÖZEL GÜN",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  tarih == null
                      ? "Tarih seçersen gün sayacı tutulur."
                      : formatDisplayDate(tarih!),
                  style: TextStyle(
                    fontSize: 12,
                    color: tarih == null
                        ? Colors.grey
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: tarih == null
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(tarih == null ? "Tarih seç" : "Değiştir"),
                      onPressed: () async {
                        final secilen = await showDatePicker(
                          context: ctx,
                          initialDate: tarih ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (secilen != null) setLocal(() => tarih = secilen);
                      },
                    ),
                    if (tarih != null)
                      TextButton(
                        onPressed: () => setLocal(() => tarih = null),
                        child: const Text("Kaldır"),
                      ),
                  ],
                ),
              ],
            ),
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
      ),
    );

    if (kaydet == true && c.text.trim().isNotEmpty) {
      final String text = c.text.trim();
      final String? date = tarih == null ? null : formatIsoDate(tarih!);

      if (_paired) {
        try {
          await CoupleService.addNote(text: text, emoji: emoji, date: date);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceFirst('Exception: ', '')),
              ),
            );
          }
        }
        return;
      }

      setState(() => _notes.add({'text': text, 'emoji': emoji, 'date': date}));
      await _saveNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kendi alanın"),
        actions: [
          const ChatThemeButton(),
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
            ),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PastelBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Sayaç ───────────────────────────────────
              const Text(
                'Kendi alanın',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('Sohbetlerin, notların ve seçtiğin küçük anlar.'),

              const SizedBox(height: 16),

              // ── Özellikler ──────────────────────────────
              const Text(
                "ÖZELLİKLER",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.4,
                children: [
                  _ozellikKart(
                    "💬",
                    "Sohbetler",
                    const ContactsScreen(),
                    kNotifLetters,
                  ),
                  _ozellikKart(
                    "🗓️",
                    "Sayaç",
                    CounterPage(onChanged: showCounterNotification),
                  ),
                  _ozellikKart(
                    "❓",
                    "Günün Sorusu",
                    const QuestionScreen(),
                    kNotifQuestions,
                  ),
                  _ozellikKart(
                    "🕰️",
                    "Anılar",
                    const TimelineScreen(),
                    kNotifTimeline,
                  ),
                  _ozellikKart(
                    "🎙️",
                    "Sesli Notlar",
                    const VoiceNotesScreen(),
                    kNotifVoice,
                  ),
                  _ozellikKart(
                    "🌠",
                    "Ortak Dilekler",
                    const WishesScreen(),
                    kNotifWishes,
                  ),
                  _ozellikKart(
                    '📚',
                    'Ders Notları',
                    const SharedCoursesScreen(),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),

              // ── Bildirim Ayarları ───────────────────────
              const Text(
                "BİLDİRİM AYARLARI",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),

              const ChatNotificationsSwitch(),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Bildirimi Göster"),
                subtitle: const Text("Üst çubukta sürekli görünsün"),
                value: _notifActive,
                onChanged: (v) {
                  setState(() => _notifActive = v);
                  widget.onSettingsChanged(_notifActive, _disguised);
                },
              ),

              const SizedBox(height: 8),

              // Mod seçim kartı
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: _disguised
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _disguised
                        ? Theme.of(context).colorScheme.outlineVariant
                        : Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _disguised ? Icons.system_update : Icons.favorite,
                          color: _disguised
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _disguised
                              ? "Gizleme Modu Aktif"
                              : "Gerçek Mod Aktif",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _disguised
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _disguised
                          ? '📳 Bildirim: "Sistem Güncellemesi"\n"$_notifTemplateDisguised"'
                          : '📳 Bildirim: "Sayaç"\n"$_notifTemplate"',
                      style: TextStyle(
                        fontSize: 12,
                        color: _disguised
                            ? Theme.of(context).colorScheme.onSecondaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: _disguised
                              ? Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer
                              : Theme.of(context).colorScheme.primary,
                        ),
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(
                          _disguised
                              ? "Gizleme yazısını düzenle"
                              : "Yazıyı düzenle",
                        ),
                        onPressed: () => _editNotifText(_disguised),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.favorite, size: 16),
                            label: const Text("Gerçek Mod"),
                            style: OutlinedButton.styleFrom(
                              disabledForegroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                              disabledBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              backgroundColor: !_disguised
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                            ),
                            onPressed: _disguised
                                ? () {
                                    setState(() => _disguised = false);
                                    widget.onSettingsChanged(
                                      _notifActive,
                                      false,
                                    );
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.system_update, size: 16),
                            label: const Text("Gizle"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _disguised
                                  ? const Color(0xff4b390c)
                                  : Theme.of(context).colorScheme.secondary,
                              disabledForegroundColor: const Color(0xff4b390c),
                              disabledBackgroundColor: const Color(0xffffedab),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              backgroundColor: _disguised
                                  ? const Color(0xffffedab)
                                  : null,
                            ),
                            onPressed: !_disguised
                                ? () {
                                    setState(() => _disguised = true);
                                    widget.onSettingsChanged(
                                      _notifActive,
                                      true,
                                    );
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 30),

              // ── PIN ─────────────────────────────────────
              const Text(
                "GÜVENLİK",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _changePin(true),
                      child: const Text("PIN Değiştir"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _changePin(false),
                      child: const Text("Sahte PIN"),
                    ),
                  ),
                ],
              ),

              const Divider(height: 30),

              // ── Gizli Resimler ──────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "GİZLİ RESİMLER",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  YeniRozet(_rozet(kNotifHidden)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: "Bildirim yazısı",
                    onPressed: () => editNotifText(context, kNotifHidden),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_a_photo),
                    onPressed: _addHiddenImage,
                  ),
                ],
              ),
              // Eşliyse paylaşımlı akış + varsa eski yereller, değilse yerel.
              _hiddenImagesSection(),

              const Divider(height: 30),

              // ── Özel Günler & Notlar ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "ÖZEL GÜNLER & NOTLAR",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  YeniRozet(_rozet(kNotifNotes)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: "Bildirim yazısı",
                    onPressed: () => editNotifText(context, kNotifNotes),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add),
                    onPressed: _addNote,
                  ),
                ],
              ),

              // Eşliyse paylaşımlı akış, değilse yerel — ikisi de aynı kartları kullanır.
              _notesSection(),

              const SizedBox(height: 80), // Alt navigasyon çubuğu boşluğu
            ],
          ),
        ),
      ),
    );
  }

  /// Resmi listeden ve diskten siler. Diskten silmezsek dosya cihazda
  /// kalmaya devam eder — gizlilik acisindan bu kabul edilemez.
  Future<void> _deleteHiddenImage(int i) async {
    if (i < 0 || i >= _hiddenImages.length) return;
    final String path = _hiddenImages[i];
    setState(() => _hiddenImages.removeAt(i));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_images', _hiddenImages);

    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Dosya zaten yoksa sorun degil; liste guncellendi.
    }
  }

  Future<void> _confirmDeleteHidden(int i) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Resmi sil"),
        content: const Text("Bu resim kalıcı olarak silinecek. Emin misin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteHiddenImage(i);
  }

  Future<void> _addHiddenImage() async {
    final picker = ImagePicker();
    // Küçültülmüş seç ki paylaşımlı hâli Firestore sınırına sığsın.
    // Orijinali al; sığmazsa compressToFit en iyi kaliteye indirir.
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    if (_paired) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await CoupleService.addHiddenImage(
          await compressToFit(await image.readAsBytes()),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }

    // Eşleşme yok — eskisi gibi yalnız bu cihazda tut.
    final directory = await getApplicationDocumentsDirectory();
    final File local = await File(
      image.path,
    ).copy('${directory.path}/h_${DateTime.now().millisecondsSinceEpoch}.png');
    setState(() => _hiddenImages.add(local.path));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_images', _hiddenImages);
  }

  Future<void> _changePin(bool isReal) async {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isReal ? "Yeni PIN" : "Yeni Sahte PIN"),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              if (c.text.length == 4) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(isReal ? 'real_pin' : 'fake_pin', c.text);
                nav.pop();
              }
            },
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  SAHTE EKRAN ANA SAYFA (decoy — masum araç ızgarası)
// ─────────────────────────────────────────
