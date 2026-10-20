import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import '../media/message_content.dart';

class MessageStars {
  static CollectionReference<Map<String, dynamic>> _refs(String uid) =>
      FirebaseFirestore.instance
          .collection('chatAccounts')
          .doc(uid)
          .collection('starredMessages');
  static String referenceId(String sourceKey, String messageId) =>
      sha256.convert(utf8.encode('$sourceKey/$messageId')).toString();
  static Stream<Set<String>> watch(String sourceKey) async* {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid!;
    await for (final snap in _refs(
      uid,
    ).where('sourceKey', isEqualTo: sourceKey).snapshots()) {
      if (CoupleService.uid != uid) return;
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final at =
              (a.data()['starredAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          final bt =
              (b.data()['starredAt'] as Timestamp?)?.millisecondsSinceEpoch ??
              0;
          return bt.compareTo(at);
        });
      yield docs.map((d) => d.data()['messageId'] as String).toSet();
    }
  }

  static Future<void> set(
    String sourceKey,
    String messageId,
    bool starred,
  ) async {
    await CoupleService.ensureReady();
    final ref = _refs(
      CoupleService.uid!,
    ).doc(referenceId(sourceKey, messageId));
    if (starred) {
      await ref.set({
        'sourceKey': sourceKey,
        'messageId': messageId,
        'starredAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  static Future<String> read(String sourceKey, String messageId) async {
    await CoupleService.ensureReady();
    final parts = sourceKey.split('/');
    final private = parts[0] == 'couple';
    String? secret;
    if (private) {
      if (await CoupleService.coupleId() != parts[1]) {
        return 'Bu özel sohbete yeniden bağlanmalısın.';
      }
      secret = await CoupleService.secret();
      if (secret == null) return 'Gizli kelimeyle bağlantı gerekli.';
    }
    final doc = await FirebaseFirestore.instance
        .collection(private ? 'couples' : 'chats')
        .doc(parts[1])
        .collection(private ? 'letters' : 'messages')
        .doc(messageId)
        .get();
    final data = doc.data();
    if (data == null) return 'Bu mesaj silinmiş.';
    final opens = data[private ? 'openDate' : 'openAt'];
    if (data['scheduled'] != false &&
        opens is Timestamp &&
        opens.toDate().isAfter(DateTime.now())) {
      return 'Bu mesaj henüz açılmadı.';
    }
    if (!private) return data['text'] as String;
    final decoded = await compute(decodeLetterBatch, {
      'secret': secret,
      'ciphers': {messageId: data['cipher']},
    });
    return decoded[messageId] ?? 'Bu mektup çözülemedi.';
  }
}

class MessageStarsScope extends StatefulWidget {
  final String sourceKey;
  final Widget child;
  final Stream<Set<String>>? stream;
  final Future<void> Function(String, bool)? update;
  const MessageStarsScope({
    super.key,
    required this.sourceKey,
    required this.child,
    this.stream,
    this.update,
  });
  static StarsData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StarsData>();
  @override
  State<MessageStarsScope> createState() => _MessageStarsScopeState();
}

class _MessageStarsScopeState extends State<MessageStarsScope> {
  late final _stream = widget.stream ?? MessageStars.watch(widget.sourceKey);
  final _pending = <String>{};
  Future<void> _toggle(String id, bool value) async {
    if (!_pending.add(id)) return;
    try {
      await (widget.update?.call(id, value) ??
          MessageStars.set(widget.sourceKey, id, value));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yıldız değiştirilemedi. Yeniden dene.'),
          ),
        );
      }
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Set<String>>(
    stream: _stream,
    builder: (_, snapshot) => StarsData(
      ids: snapshot.data ?? {},
      toggle: _toggle,
      child: widget.child,
    ),
  );
}

class StarsData extends InheritedWidget {
  final Set<String> ids;
  final Future<void> Function(String, bool) toggle;
  const StarsData({
    super.key,
    required this.ids,
    required this.toggle,
    required super.child,
  });
  @override
  bool updateShouldNotify(StarsData oldWidget) =>
      !setEquals(ids, oldWidget.ids);
}

class StarredMessagesButton extends StatelessWidget {
  final String sourceKey;
  const StarredMessagesButton({super.key, required this.sourceKey});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Yıldızlı mesajlar',
    icon: const Icon(Icons.star_outline),
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StarredMessagesScreen(sourceKey: sourceKey),
      ),
    ),
  );
}

class StarredMessagesScreen extends StatefulWidget {
  final String sourceKey;
  const StarredMessagesScreen({super.key, required this.sourceKey});
  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  late final _stream = MessageStars.watch(widget.sourceKey);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yıldızlı mesajlar')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Yıldızlar sana özeldir. Eklerin saklama süresi değişmez.',
          ),
        ),
        Expanded(
          child: StreamBuilder<Set<String>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                  child: Text(
                    'Yıldızlar yüklenemedi. Sohbetten yeniden açabilirsin.',
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ids = snap.data!.toList();
              if (ids.isEmpty) {
                return const Center(child: Text('Henüz yıldızlı mesaj yok.'));
              }
              return ListView.builder(
                itemCount: ids.length,
                itemBuilder: (_, i) => _StarredEntry(
                  key: ValueKey(ids[i]),
                  sourceKey: widget.sourceKey,
                  id: ids[i],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _StarredEntry extends StatefulWidget {
  final String sourceKey;
  final String id;
  const _StarredEntry({super.key, required this.sourceKey, required this.id});
  @override
  State<_StarredEntry> createState() => _StarredEntryState();
}

class _StarredEntryState extends State<_StarredEntry> {
  late final _text = MessageStars.read(widget.sourceKey, widget.id);
  bool _busy = false;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FutureBuilder<String>(
              future: _text,
              builder: (_, snap) => snap.hasError
                  ? const Text('Bu mesaja erişilemiyor.')
                  : snap.hasData
                  ? MessageContent(text: snap.data!)
                  : const LinearProgressIndicator(),
            ),
          ),
          IconButton(
            tooltip: 'Yıldızı kaldır',
            icon: const Icon(Icons.star),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await MessageStars.set(
                        widget.sourceKey,
                        widget.id,
                        false,
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Yıldız kaldırılamadı. Yeniden dene.',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
        ],
      ),
    ),
  );
}
