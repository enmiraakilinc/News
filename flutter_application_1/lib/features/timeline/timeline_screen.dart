import '../../core/utils/sync_state.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';
import '../media/image_util.dart';
import '../../core/notifications/notif_prefs.dart';

const List<String> _aylar = [
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
String _tarih(DateTime d) => '${d.day} ${_aylar[d.month - 1]} ${d.year}';
String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Anıların tarih ve yerle sıralandığı zaman tüneli.
///
/// Eşleşme varsa fotoğraflar mektuplar gibi UÇTAN UCA şifrelenip Firestore
/// üzerinden senkronlanır → iki telefonda da görünür. Eşleşme yoksa eski
/// yerel-sadece davranış korunur. Bu telefonda kalmış eski (paylaşılmamış)
/// anılar kaybolmaz; ayrı bir bölümde gösterilir ve tek dokunuşla paylaşılabilir.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const String _key = 'timeline_v1';

  bool _loading = true;
  String? _coupleId;
  String? _secret;
  bool get _paired => _coupleId != null && _secret != null;
  Stream<List<TimelineMemory>>? _sharedStream;
  int _sharedLimit = 12;

  void _loadMoreShared() {
    setState(() {
      _sharedLimit += 12;
      _sharedStream = CoupleService.timelineStream(
        _coupleId!,
        _secret!,
        limit: _sharedLimit,
      );
    });
  }

  void _retryShared() {
    CoupleService.resetConnection();
    setState(() {
      _sharedStream = CoupleService.timelineStream(
        _coupleId!,
        _secret!,
        limit: _sharedLimit,
      );
    });
  }

  // Bu telefonda kalmış, henüz paylaşılmamış eski anılar.
  List<Map<String, dynamic>> _localItems = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    await _loadLocal();
    if (!mounted) return;
    setState(() {
      _coupleId = cid;
      _secret = sec;
      _sharedStream = cid != null && sec != null
          ? CoupleService.timelineStream(cid, sec)
          : null;
      _loading = false;
    });
    // Eşleşme varsa, bu telefonda kalmış eski anıları kullanıcıyı uğraştırmadan
    // arka planda paylaşıma taşı — "her şey ikimizde de görünsün" beklentisi bu.
    if (_paired) unawaited(_autoShareLocals());
  }

  /// Eski yerel anıları sessizce paylaşıma yükler. Sığmayanlar yerelde kalır
  /// (kullanıcı yine elle "Paylaş" diyebilir). Hata olursa sessizce geçer.
  Future<void> _autoShareLocals() async {
    if (_localItems.isEmpty) return;
    // Kopya üzerinde dön: liste yükleme sırasında değişiyor.
    for (final item in List<Map<String, dynamic>>.from(_localItems)) {
      if (!mounted) return;
      final path = item['path'] as String;
      final file = File(path);
      try {
        if (!await file.exists()) {
          final i = _localItems.indexOf(item);
          if (i >= 0) await _removeLocalAt(i);
          continue;
        }
        final bytes = await file.readAsBytes();
        final date =
            DateTime.tryParse(item['date'] as String) ?? DateTime.now();
        await _uploadWithFallback(
          bytes,
          date,
          item['place'] as String,
          item['note'] as String,
        );
        final i = _localItems.indexOf(item);
        if (i >= 0) await _removeLocalAt(i, deleteFile: true);
      } catch (_) {
        // Sığmadı/hata — yerelde kalsın, kullanıcı elle paylaşabilir.
      }
    }
  }

  // ── Yerel (eski) anılar ──────────────────────────────────
  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      list = (jsonDecode(raw) as List)
          .map(
            (e) => <String, dynamic>{
              'path': (e['path'] ?? '').toString(),
              'date': (e['date'] ?? '').toString(),
              'place': (e['place'] ?? '').toString(),
              'note': (e['note'] ?? '').toString(),
            },
          )
          .toList();
    }
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    _localItems = list;
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_localItems));
  }

  Future<void> _removeLocalAt(int i, {bool deleteFile = false}) async {
    if (i < 0 || i >= _localItems.length) return;
    final path = _localItems[i]['path'] as String;
    setState(() => _localItems.removeAt(i));
    await _saveLocal();
    if (deleteFile) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ── Ekleme ───────────────────────────────────────────────
  /// Fotoğraf seçtirir. Eşliyse paylaşımlı ekler, değilse yerel ekler.
  Future<void> _add() async {
    final picker = ImagePicker();
    // image_picker kendi içinde küçültür/sıkıştırır — ekstra paket gerekmez.
    // Firestore belge sınırına (~1MB) rahat sığsın diye 1080px + kalite 55.
    // Orijinali al; gerekirse compressToFit sığdıracak kadar küçültür.
    final XFile? img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null || !mounted) return;

    final meta = await _askMeta(context);
    if (meta == null) return;
    final date = DateTime.tryParse(meta['date']!) ?? DateTime.now();

    if (_paired) {
      final bytes = await img.readAsBytes();
      await _uploadShared(bytes, date, meta['place']!, meta['note']!);
    } else {
      await _addLocalFile(img, meta);
    }
  }

  /// Paylaşımlı ekleme — şifreli olarak Firestore'a yazar.
  Future<void> _uploadShared(
    Uint8List bytes,
    DateTime date,
    String place,
    String note,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _uploadWithFallback(bytes, date, place, note);
      messenger.showSnackBar(
        const SnackBar(content: Text('Anı eklendi — ikinizde de görünecek 💜')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  /// Fotoğrafı JPEG'e sıkıştırıp yükler. Eski (tam boyut) fotoğraflar da
  /// böylece Firestore ~1MB sınırına rahat sığar.
  Future<void> _uploadWithFallback(
    Uint8List bytes,
    DateTime date,
    String place,
    String note,
  ) async {
    final small = await _compress(bytes);
    await CoupleService.addTimelineMemory(
      imageBytes: small,
      date: date,
      place: place,
      note: note,
    );
  }

  /// Sığıyorsa orijinali korur; sığmıyorsa sığacak en iyi kaliteye indirir.
  Future<Uint8List> _compress(Uint8List src) => compressToFit(src);

  /// Eşleşme yokken eski davranış: dosyayı cihaza kopyalayıp yerel kaydeder.
  Future<void> _addLocalFile(XFile img, Map<String, String> meta) async {
    final dir = await getApplicationDocumentsDirectory();
    final local = await File(
      img.path,
    ).copy('${dir.path}/ani_${DateTime.now().millisecondsSinceEpoch}.png');
    setState(() {
      _localItems.add({
        'path': local.path,
        'date': meta['date']!,
        'place': meta['place']!,
        'note': meta['note']!,
      });
      _localItems.sort(
        (a, b) => (b['date'] as String).compareTo(a['date'] as String),
      );
    });
    await _saveLocal();
  }

  /// Bu telefondaki eski bir anıyı paylaşımlıya taşır.
  Future<void> _shareLocal(int i) async {
    final messenger = ScaffoldMessenger.of(context);
    final item = _localItems[i];
    final file = File(item['path'] as String);
    if (!await file.exists()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Dosya bulunamadı, anı kaldırılıyor.')),
      );
      await _removeLocalAt(i);
      return;
    }
    final date = DateTime.tryParse(item['date'] as String) ?? DateTime.now();
    try {
      final bytes = await file.readAsBytes();
      await _uploadWithFallback(
        bytes,
        date,
        item['place'] as String,
        item['note'] as String,
      );
      await _removeLocalAt(i, deleteFile: true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Anı paylaşıldı 💜')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<Map<String, String>?> _askMeta(BuildContext context) {
    final placeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Anı Bilgisi"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(_tarih(date)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final s = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (s != null) setLocal(() => date = s);
                      },
                      child: const Text("Tarih seç"),
                    ),
                  ],
                ),
                TextField(
                  controller: placeCtrl,
                  decoration: const InputDecoration(
                    labelText: "Yer (örn: Kapadokya)",
                  ),
                ),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: "Not (isteğe bağlı)",
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("İptal"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, {
                'date': _iso(date),
                'place': placeCtrl.text.trim(),
                'note': noteCtrl.text.trim(),
              }),
              child: const Text("Kaydet"),
            ),
          ],
        ),
      ),
    );
  }

  // ── Silme ────────────────────────────────────────────────
  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anıyı sil"),
        content: const Text("Bu anı kalıcı olarak silinecek. Emin misin?"),
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

  Future<void> _deleteShared(String id) async {
    if (!await _confirmDelete()) return;
    await CoupleService.deleteTimelineMemory(id);
  }

  /// Kartta fotoğrafın hangi kısmının görüneceğini kaydırarak seçtirir.
  Future<void> _adjustFocus(TimelineMemory m) async {
    if (m.image == null) return;
    double focus = m.focus.clamp(-1.0, 1.0);

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("Görünen kısmı seç"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Fotoğrafı yukarı/aşağı kaydırarak kartta hangi kısmının "
                "görüneceğini ayarla.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              // Kartla aynı oranda önizleme; sürükleyerek de ayarlanır.
              GestureDetector(
                onVerticalDragUpdate: (d) {
                  setLocal(() {
                    focus = (focus - d.delta.dy / 60).clamp(-1.0, 1.0);
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    m.image!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment(0, focus),
                    cacheWidth: kDetailMaxSide,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.vertical_align_top,
                    size: 18,
                    color: Colors.grey,
                  ),
                  Expanded(
                    child: Slider(
                      value: focus,
                      min: -1,
                      max: 1,
                      onChanged: (v) => setLocal(() => focus = v),
                    ),
                  ),
                  const Icon(
                    Icons.vertical_align_bottom,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
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
      ),
    );

    if (kaydet == true) await CoupleService.setTimelineFocus(m.id, focus);
  }

  // ── İndirme (sahibinden izinli) ──
  /// Kendi fotoğrafımsa doğrudan kaydeder; eşinse ondan izin ister.
  /// Onay gelince kaydetme işini gizli ana ekrandaki dinleyici yapar.
  Future<void> _askDownload(TimelineMemory m) async {
    final messenger = ScaffoldMessenger.of(context);
    if (m.fromMe) {
      await _saveToGallery(m.image);
      return;
    }
    try {
      await CoupleService.requestDownload(
        kind: 'timeline',
        itemId: m.id,
        ownerUid: m.ownerUid,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "İzin istendi — eşin onaylayınca galerine kaydedilecek.",
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
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

  Future<void> _deleteLocal(int i) async {
    if (!await _confirmDelete()) return;
    await _removeLocalAt(i, deleteFile: true);
  }

  // ── Görüntüleme ──────────────────────────────────────────
  void _viewImage(ImageProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: InteractiveViewer(child: Image(image: provider)),
            ),
          ),
        ),
      ),
    );
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ── Yapı ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Anılar"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: "Bildirim yazısı",
            onPressed: () => editNotifText(context, kNotifTimeline),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_a_photo),
        label: const Text("Anı Ekle"),
        onPressed: _add,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _paired
          ? _buildPaired()
          : _buildUnpaired(),
    );
  }

  /// Eşleşme yok: eski yerel davranış + eşleşmeye davet eden bilgi kartı.
  Widget _buildUnpaired() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.link_off,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Fotoğrafların ikinizde de görünmesi için 'Geleceğe Mektup'tan "
                  "eşleşin. Şimdi eklediklerin bu telefonda kalır; eşleşince "
                  "'Paylaş' ile karşıya taşıyabilirsin.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_localItems.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text(
              "Henüz anı yok.\n'Anı Ekle' ile ilk fotoğrafını ekle.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          for (int i = 0; i < _localItems.length; i++) _localTile(i),
      ],
    );
  }

  /// Eşleşme var: paylaşımlı canlı akış + varsa eski yerel anılar bölümü.
  Widget _buildPaired() {
    return StreamBuilder<List<TimelineMemory>>(
      stream: _sharedStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return SyncError(label: 'Kayıtlar', onRetry: _retryShared);
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shared = snap.data ?? [];
        final bosVeYerelYok = shared.isEmpty && _localItems.isEmpty;
        if (bosVeYerelYok) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Henüz anı yok.\n'Anı Ekle' ile ilk fotoğrafınızı ekleyin.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          itemCount:
              shared.length +
              (shared.length >= _sharedLimit ? 1 : 0) +
              (_localItems.isEmpty ? 0 : _localItems.length + 1),
          itemBuilder: (context, index) {
            if (index < shared.length) return _sharedTile(shared[index]);
            if (shared.length >= _sharedLimit && index == shared.length) {
              return TextButton.icon(
                onPressed: _loadMoreShared,
                icon: const Icon(Icons.expand_more),
                label: const Text('Önceki anıları göster'),
              );
            }
            final localIndex =
                index - shared.length - (shared.length >= _sharedLimit ? 1 : 0);
            if (localIndex == 0) {
              return const ListTile(
                leading: Icon(Icons.phone_iphone),
                title: Text('Bu telefonda (payla??lmad?)'),
              );
            }
            return _localTile(localIndex - 1, shareable: true);
          },
        );
      },
    );
  }

  // ── Kart yapıları ────────────────────────────────────────
  /// Ortak zaman-çizgisi satırı: solda nokta+çizgi, sağda kart.
  Widget _row({
    required DateTime date,
    required String place,
    required String note,
    required Widget image,
    VoidCallback? onView,
    String? tag,
    required List<Widget> actions,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 3,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _tarih(date),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (place.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.place, size: 14, color: Colors.grey),
                        Expanded(
                          child: Text(
                            place,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(onTap: onView, child: image),
                  ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(note),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sharedTile(TimelineMemory m) {
    final Widget image = m.image != null
        ? Image.memory(
            m.image!,
            height: 180,
            width: double.infinity,
            fit: BoxFit.contain,
            alignment: Alignment(0, m.focus.clamp(-1.0, 1.0)),
            cacheWidth: kThumbMaxSide,
          )
        : Container(
            height: 180,
            color: Theme.of(context).colorScheme.surfaceContainer,
            alignment: Alignment.center,
            child: const Text(
              "Fotoğraf çözülemedi\n(gizli kelime farklı olabilir)",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
    return _row(
      date: m.date,
      place: m.place,
      note: m.note,
      image: image,
      tag: m.fromMe ? "Sen ekledin" : "Eşin ekledi",
      onView: m.image != null ? () => _viewImage(MemoryImage(m.image!)) : null,
      actions: [
        if (m.image != null)
          TextButton.icon(
            icon: const Icon(Icons.crop, size: 18),
            label: const Text("Ayarla"),
            onPressed: () => _adjustFocus(m),
          ),
        if (m.image != null)
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text("İndir"),
            onPressed: () => _askDownload(m),
          ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text("Sil"),
          onPressed: () => _deleteShared(m.id),
        ),
      ],
    );
  }

  Widget _localTile(int i, {bool shareable = false}) {
    final item = _localItems[i];
    final d = DateTime.tryParse(item['date'] as String) ?? DateTime.now();
    final path = item['path'] as String;
    return _row(
      date: d,
      place: item['place'] as String,
      note: item['note'] as String,
      image: Image.file(
        File(path),
        height: 180,
        width: double.infinity,
        fit: BoxFit.contain,
        cacheWidth: kThumbMaxSide,
      ),
      tag: shareable ? "Bu telefonda" : null,
      onView: () => _viewImage(FileImage(File(path))),
      actions: [
        if (shareable)
          TextButton.icon(
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text("Paylaş"),
            onPressed: () => _shareLocal(i),
          ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text("Sil"),
          onPressed: () => _deleteLocal(i),
        ),
      ],
    );
  }
}
