import '../media/message_content.dart';
import 'search/message_search.dart';
import '../contacts/contact_names.dart';
import '../../core/theme/chat_theme.dart';
import 'chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pair/couple_service.dart';
import '../location/location_share.dart';
import '../media/chat_media.dart';
import '../contacts/contact_details_screen.dart';
import '../../core/utils/user_errors.dart';

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
String _ikiHane(int n) => n.toString().padLeft(2, '0');

/// Tarih + saat: "5 Mart 2026, 14:32" (gönderim/açılış anını göstermek için).
String _tarihSaat(DateTime d) =>
    '${_tarih(d)}, ${_ikiHane(d.hour)}:${_ikiHane(d.minute)}';

/// Saat: "09:00"

/// Geleceğe mektup ekranı. Eşleşme yoksa önce eşleşme ekranını gösterir.
class LettersScreen extends StatefulWidget {
  const LettersScreen({super.key});

  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  bool _loading = true;
  String? _coupleId;
  String? _secret;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    if (!mounted) return;
    setState(() {
      _coupleId = cid;
      _secret = sec;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_coupleId == null || _secret == null) {
      return _PairingView(onPaired: _refresh);
    }
    return _LettersView(
      coupleId: _coupleId!,
      secret: _secret!,
      onUnpair: () async {
        await CoupleService.unpairLocal();
        _refresh();
      },
    );
  }
}

// ─────────────────────────────────────────
//  EŞLEŞME EKRANI
// ─────────────────────────────────────────
class _PairingView extends StatefulWidget {
  final VoidCallback onPaired;
  const _PairingView({required this.onPaired});

  @override
  State<_PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<_PairingView> {
  bool _busy = false;

  Future<void> _loginFlow() async {
    final word = await _askSecret(context, "Gizli Kelime ile Giriş");
    if (word == null || word.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await CoupleService.signInWithSecret(word);
      if (mounted) widget.onPaired();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFlow() async {
    final secret = await _askSecret(context, "Gizli Kelime Belirle");
    if (secret == null || secret.isEmpty) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final code = await CoupleService.createCouple(secret);
      if (!mounted) return;
      setState(() => _busy = false);
      await _showCode(code);
      widget.onPaired();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _joinFlow() async {
    final code = await _askText(
      context,
      title: "Davet Kodu",
      hint: "6 haneli kod",
      number: true,
      maxLen: 6,
    );
    if (code == null || code.trim().isEmpty) return;
    if (!mounted) return;
    final secret = await _askSecret(context, "Gizli Kelime");
    if (secret == null || secret.isEmpty) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await CoupleService.joinCouple(code, secret);
      widget.onPaired();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _showCode(String code) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Davet Kodu"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Bu kodu ve gizli kelimeyi ilet. Diğer telefondan 'Koda Katıl' "
              "seçilip bunlar girilsin.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              code,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Tamam"),
          ),
        ],
      ),
    );
  }

  String _msg(Object e) => userError(e);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mektuplar")),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("💌", style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  const Text(
                    "Bağına giriş yap",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Daha önce eşleştiysen yalnızca gizli kelimen yeterli. "
                    "Davet kodu ilk eşleşmede kullanılır.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text("Gizli Kelime ile Giriş"),
                      onPressed: _loginFlow,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add_link),
                      label: const Text("Yeni Bağ Oluştur"),
                      onPressed: _createFlow,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text("Koda Katıl"),
                      onPressed: _joinFlow,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "🔒 Gizli kelime sadece ikinizde kalır, sunucuya "
                      "gönderilmez. Mektuplarınızı bu kelime olmadan kimse "
                      "(uygulama dahil) okuyamaz.",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────
//  MEKTUP LİSTESİ (hediye kutuları)
// ─────────────────────────────────────────
class _LettersView extends StatefulWidget {
  final String coupleId;
  final String secret;
  final VoidCallback onUnpair;

  const _LettersView({
    required this.coupleId,
    required this.secret,
    required this.onUnpair,
  });

  @override
  State<_LettersView> createState() => _LettersViewState();
}

class _LettersViewState extends State<_LettersView> {
  int _messageLimit = 100;
  @override
  void initState() {
    super.initState();
    ContactNames.changes.addListener(_nameChanged);
    ContactNames.load();
  }

  void _nameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactNames.changes.removeListener(_nameChanged);
    super.dispose();
  }

  Future<void> _action(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşlem tamamlanamadı. Tekrar dene.')),
        );
      }
    }
  }

  Letter? _reply;
  Future<void> Function(String, DateTime?) get _sendHandler {
    final replyToId = _reply?.id;
    return (text, openDate) => CoupleService.sendLetter(
      text: text,
      emoji: '💌',
      openDate: openDate,
      replyToId: replyToId,
    );
  }

  final Set<String> _pendingReads = {};

  void _markVisibleRead(Letter letter) {
    if (letter.fromMe ||
        !letter.acildi ||
        letter.readByRecipient ||
        !_pendingReads.add(letter.id)) {
      return;
    }
    CoupleService.markLetterRead(letter.id)
        .catchError((Object _) {})
        .whenComplete(() => _pendingReads.remove(letter.id));
  }

  /// Akış bir kez kurulur; her yeniden çizimde yeniden bağlanmasın.
  late Stream<List<Letter>> _stream = CoupleService.lettersStream(
    widget.coupleId,
    widget.secret,
  );

  /// "Tekrar dene": oturumu sıfırdan kurup akışı yeniden bağlar.
  void _retry() {
    CoupleService.resetConnection();
    setState(() {
      _stream = CoupleService.lettersStream(
        widget.coupleId,
        widget.secret,
        limit: _messageLimit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChatScaffold(
      starsSource: 'couple/${widget.coupleId}',
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: 'Mesajlarda ara',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => MessageSearchScreen(
                  source: 'couple/${widget.coupleId}',
                  secret: widget.secret,
                ),
              ),
            ),
          ),
        ],
        title: ContactChatHeader(
          contactId: ContactNames.posniId,
          fallbackName: 'Posni',
          sourceKey: 'couple/${widget.coupleId}',
          onUnpair: () => _confirmUnpair(context),
        ),
      ),
      bottomNavigationBar: ChatComposer(
        coupleId: widget.coupleId,
        onShareLocation: () => LocationShares.send(
          context,
          coupleId: widget.coupleId,
          onSend: (text, date) =>
              CoupleService.sendLetter(text: text, emoji: '📍', openDate: date),
        ),
        replyPreview: _reply?.text,
        onCancelReply: () => setState(() => _reply = null),
        onSend: _sendHandler,
      ),
      body: StreamBuilder<List<Letter>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Hata varsa ama elimizde mektup varsa listeyi silme — sadece uyar.
          final letters = snap.data ?? [];
          final photoMessages = [
            for (final letter in letters.reversed)
              if (letter.acildi && letter.text != null) letter.text!,
          ];
          final byId = {for (final letter in letters) letter.id: letter};
          if (snap.hasError && letters.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Mektuplara şu an ulaşılamıyor.\n"
                      "İnternetini kontrol edip tekrar dene.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Tekrar dene"),
                      onPressed: _retry,
                    ),
                  ],
                ),
              ),
            );
          }
          if (letters.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Henüz mektup yok.\nAşağıya yazıp ilk mektubunu gönder.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount:
                letters.length + (letters.length >= _messageLimit ? 1 : 0),
            itemBuilder: (c, i) {
              if (i == letters.length) {
                return TextButton.icon(
                  onPressed: () => setState(() {
                    _messageLimit += 100;
                    _stream = CoupleService.lettersStream(
                      widget.coupleId,
                      widget.secret,
                      limit: _messageLimit,
                    );
                  }),
                  icon: const Icon(Icons.history),
                  label: const Text('Eski mektupları yükle'),
                );
              }
              final letter = letters[i];
              if (letter.acildi) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _markVisibleRead(letter);
                });
              }
              final day = letter.sentDate ?? letter.openDate;
              final older = i + 1 < letters.length ? letters[i + 1] : null;
              final olderDay = older?.sentDate ?? older?.openDate;
              final showDate =
                  olderDay == null ||
                  day.year != olderDay.year ||
                  day.month != olderDay.month ||
                  day.day != olderDay.day;
              final original = byId[letter.replyToId];
              return Column(
                children: [
                  if (showDate)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Chip(
                        label: Text(
                          _tarih(day),
                          style: const TextStyle(fontSize: 11),
                        ),
                        side: BorderSide.none,
                      ),
                    ),
                  MessageBubble(
                    copyOrder: day.millisecondsSinceEpoch,
                    photoMessages: photoMessages,
                    starMessageId: letter.acildi ? letter.id : null,
                    mine: letter.fromMe,
                    author: letter.fromMe
                        ? null
                        : ContactNames.name(ContactNames.posniId, 'Posni'),
                    text: letter.text ?? 'Geleceğe bırakılmış bir mektup',
                    time: letter.acildi
                        ? '${_ikiHane(day.hour)}:${_ikiHane(day.minute)}${letter.edited ? ' · düzenlendi' : ''}'
                        : 'Açılış: ${_tarihSaat(letter.openDate)}',
                    quoted:
                        original?.text ??
                        (letter.replyToId != null ? 'Bir mektuba yanıt' : null),
                    status: letter.fromMe
                        ? (letter.sentDate == null
                              ? 'Gönderiliyor…'
                              : letter.readByRecipient
                              ? '✓✓ Okundu'
                              : '✓ İletildi')
                        : null,
                    reactions: letter.reactions,
                    onReact: letter.acildi
                        ? (emoji) => _action(
                            () => CoupleService.reactLetter(
                              letter.id,
                              emoji,
                              letter.reactions[CoupleService.uid],
                            ),
                          )
                        : null,
                    onEdit:
                        letter.fromMe &&
                            letter.acildi &&
                            !letter.text!.startsWith(locationPrefix) &&
                            !letter.text!.startsWith(attachmentPrefix) &&
                            !letter.text!.startsWith(mediaPrefix)
                        ? () async {
                            final text = await editMessage(
                              context,
                              letter.text!,
                            );
                            if (text != null) {
                              await _action(
                                () => CoupleService.editLetter(letter.id, text),
                              );
                            }
                          }
                        : null,
                    scheduled: !letter.acildi,
                    onTap: () => _openLetter(context, letter),
                    onReply: letter.acildi
                        ? () {
                            if (!letter.fromMe) {
                              CoupleService.markLetterRead(letter.id);
                            }
                            setState(() => _reply = letter);
                          }
                        : null,
                    onDelete: () => _confirmDeleteLetter(context, letter),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _confirmUnpair(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Bağı kaldır"),
        content: const Text(
          "Bu telefondaki eşleşme kaldırılacak. Mektuplar silinmez; "
          "istersen tekrar yalnızca gizli kelimeyle bağlanabilirsin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Kaldır"),
          ),
        ],
      ),
    );
    if (ok == true) widget.onUnpair();
  }

  void _openLetter(BuildContext context, Letter l) {
    if (!l.acildi) {
      final kalan = l.openDate.difference(DateTime.now()).inDays;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Bu mektup ${_tarihSaat(l.openDate)} tarihinde açılacak"
            "${kalan > 0 ? ' (${kalan + 1} gün kaldı)' : ''} 🎁",
          ),
        ),
      );
      return;
    }
    // Bana gelen ve henüz okumadığım bir mektubu açıyorsam "okundu" işaretle.
    // Gönderen bunu "Okundu ✓✓" olarak görecek; kart bende soluklaşacak.
    if (!l.fromMe && !l.readByRecipient) {
      CoupleService.markLetterRead(l.id);
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          // Uzun mektuplar taşmasın: yüksekliği ekranın %80'iyle sınırla,
          // metni de kendi içinde kaydırılabilir yap. Karakter sınırı yok.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 4),
                Text(
                  l.fromMe ? "Senin yazdığın mektup" : "Sana bir mektup",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (l.sentDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Gönderildi: ${_tarihSaat(l.sentDate!)}",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
                if (l.readAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Açıldı: ${_tarihSaat(l.readAt!)}",
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Metin hem kaydırılabilir hem seçilip kopyalanabilir.
                Flexible(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        l.text ?? '',
                        style: const TextStyle(fontSize: 16, height: 1.4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Tüm metni tek dokunuşla panoya al.
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text("Kopyala"),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: l.text ?? ''));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Mektup kopyalandı")),
                        );
                      },
                    ),
                    // Eşin mektubuna doğrudan yanıt yaz.
                    if (!l.fromMe)
                      TextButton.icon(
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text("Yanıtla"),
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() => _reply = l);
                        },
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Kapat"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteLetter(BuildContext context, Letter l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mektubu sil"),
        content: const Text(
          "Bu mektup her iki telefondan da kalıcı olarak silinecek. "
          "Emin misin?",
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
    if (ok == true) await CoupleService.deleteLetter(l.id);
  }
}

// ── Ortak küçük yardımcılar ──
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String hint,
  bool number = false,
  int? maxLen,
}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLength: maxLen,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("İptal"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text("Tamam"),
        ),
      ],
    ),
  );
}

Future<String?> _askSecret(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "İkinizin de aynısını gireceği gizli bir kelime. Sözlü olarak "
            "kararlaştırın; yalnızca bu cihazda saklanır. Sunucuda kelimenin özeti tutulur.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: "örn: kelebek2024"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("İptal"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text("Tamam"),
        ),
      ],
    ),
  );
}
