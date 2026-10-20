import '../../core/utils/sync_state.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../pair/couple_service.dart';
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

/// Çiftin ortak dilek / yapılacaklar listesi. Maddeler mektuplar gibi uçtan
/// uca şifrelenip Firestore üzerinden iki telefonda da senkronlanır.
/// Bir dilek gerçekleşince fotoğrafı doğrudan Anılar'ne eklenebilir.
class WishesScreen extends StatefulWidget {
  const WishesScreen({super.key});

  @override
  State<WishesScreen> createState() => _WishesScreenState();
}

class _WishesScreenState extends State<WishesScreen> {
  bool _loading = true;
  String? _coupleId;
  String? _secret;
  bool get _paired => _coupleId != null && _secret != null;
  Stream<List<Wish>>? _sharedStream;

  void _retryShared() {
    CoupleService.resetConnection();
    setState(() {
      _sharedStream = CoupleService.wishesStream(_coupleId!, _secret!);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    if (!mounted) return;
    setState(() {
      _coupleId = cid;
      _secret = sec;
      _sharedStream = cid != null && sec != null
          ? CoupleService.wishesStream(cid, sec)
          : null;
      _loading = false;
    });
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  // ── Ekleme ───────────────────────────────────────────────
  Future<void> _addWish() async {
    final c = TextEditingController();
    final ekle = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yeni Dilek"),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            hintText: "Örn: Birlikte Kapadokya'da balona binmek 🎈",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Ekle"),
          ),
        ],
      ),
    );
    if (ekle == true && c.text.trim().isNotEmpty) {
      try {
        await CoupleService.addWish(c.text.trim());
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_msg(e))));
        }
      }
    }
  }

  // ── İşaretleme + tünel köprüsü ───────────────────────────
  Future<void> _toggle(Wish w) async {
    final yeni = !w.done;
    try {
      await CoupleService.setWishDone(w.id, yeni);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(e))));
      }
      return;
    }
    // Yeni gerçekleşen bir dilek → fotoğrafını tünele eklemeyi teklif et.
    if (yeni && mounted) {
      final foto = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Dileğiniz gerçek oldu! 🎉"),
          content: Text(
            '"${w.text}"\n\nBunun bir fotoğrafını anılara eklemek '
            'ister misin? İkinizde de görünür.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Şimdi değil"),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: const Text("Fotoğraf Ekle"),
            ),
          ],
        ),
      );
      if (foto == true) await _addPhotoToTimeline(w);
    }
  }

  /// Gerçekleşen dileğin fotoğrafını, notu hazır şekilde tünele ekler.
  Future<void> _addPhotoToTimeline(Wish w) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 55,
    );
    if (img == null) return;
    try {
      final bytes = await img.readAsBytes();
      await CoupleService.addTimelineMemory(
        imageBytes: bytes,
        date: DateTime.now(),
        place: '',
        note: 'Dileğimiz gerçek oldu 🌟 ${w.text}',
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Anılara eklendi 🌟 İkinizde de görünecek.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _delete(Wish w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Dileği sil"),
        content: const Text(
          "Bu dilek iki telefondan da silinecek. Emin misin?",
        ),
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
    if (ok == true) await CoupleService.deleteWish(w.id);
  }

  // ── Yapı ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ortak Dilekler"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: "Bildirim yazısı",
            onPressed: () => editNotifText(context, kNotifWishes),
          ),
        ],
      ),
      floatingActionButton: _paired
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text("Dilek Ekle"),
              onPressed: _addWish,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _paired
          ? _buildList()
          : _buildNotPaired(),
    );
  }

  Widget _buildNotPaired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("🌠", style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              "Ortak dilek listesi için eşleşme gerekli",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "'Geleceğe Mektup' bölümünden eşinle eşleşince dilekleriniz "
              "ikinizde de görünür.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<Wish>>(
      stream: _sharedStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return SyncError(label: 'Kayıtlar', onRetry: _retryShared);
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final wishes = snap.data ?? [];
        if (wishes.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Henüz dilek yok.\n'Dilek Ekle' ile ilk hayalinizi yazın 🌠",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        final pending = wishes.where((w) => !w.done).toList();
        final done = wishes.where((w) => w.done).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            if (pending.isNotEmpty) ...[
              _header("✨ Hayallerimiz", pending.length),
              ...pending.map(_tile),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 8),
              _header("🎉 Gerçekleşenler", done.length),
              ...done.map(_tile),
            ],
          ],
        );
      },
    );
  }

  Widget _header(String baslik, int adet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        "$baslik  ($adet)",
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _tile(Wish w) {
    final done = w.done;
    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: done,
              shape: const CircleBorder(),
              activeColor: Theme.of(context).colorScheme.primary,
              onChanged: (_) => _toggle(w),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? "🎉 Gerçekleşti${w.doneAt != null ? ' · ${_tarih(w.doneAt!)}' : ''}"
                        : (w.fromMe ? "Sen ekledin" : "Eşin ekledi"),
                    style: TextStyle(
                      fontSize: 11,
                      color: done ? Colors.green.shade600 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (done)
              IconButton(
                icon: const Icon(Icons.add_a_photo, size: 20),
                tooltip: "Anılara fotoğraf ekle",
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => _addPhotoToTimeline(w),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(w),
            ),
          ],
        ),
      ),
    );
    return done ? Opacity(opacity: 0.7, child: card) : card;
  }
}
