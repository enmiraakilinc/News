import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../pair/couple_service.dart';
import '../../media/message_content.dart';
import '../../../core/theme/chat_theme.dart';
import '../../../core/utils/search_text.dart';

class SearchMessage {
  final String id, text;
  final DateTime date;
  final bool mine;
  late final String preview = messagePreview(text);
  late final String searchable = searchText(preview);
  SearchMessage(this.id, this.text, this.date, this.mine);
}

bool searchableMessageOpen(
  Map<String, dynamic> data,
  String dateKey,
  DateTime now,
) {
  if (data['scheduled'] == false) return true;
  final date = data[dateKey];
  return date is Timestamp && !date.toDate().isAfter(now);
}

class MessageSearchPager {
  final String source;
  final String? secret;
  MessageSearchPager(this.source, {this.secret});
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool done = false;
  int scanned = 0;
  final messages = <SearchMessage>[];
  final _decoder = LetterDecodeCache();

  Future<void> next() async {
    if (done) return;
    await CoupleService.ensureReady();
    final pair = source.startsWith('couple/');
    final id = source.substring(source.indexOf('/') + 1);
    var query = FirebaseFirestore.instance
        .collection(pair ? 'couples' : 'chats')
        .doc(id)
        .collection(pair ? 'letters' : 'messages')
        .orderBy(pair ? 'createdAt' : 'sentAt', descending: true)
        .limit(100);
    if (_cursor != null) query = query.startAfterDocument(_cursor!);
    final page = await query.get();
    final visible = page.docs
        .where(
          (d) => searchableMessageOpen(
            d.data(),
            pair ? 'openDate' : 'openAt',
            DateTime.now(),
          ),
        )
        .toList();
    final decoded = pair
        ? await _decoder.decode(secret!, {
            for (final d in visible) d.id: d.data()['cipher'] as String,
          })
        : <String, String?>{};
    final added = <SearchMessage>[];
    for (final document in visible) {
      final data = document.data();
      final text = pair ? decoded[document.id] : data['text'] as String?;
      if (text == null) continue;
      final date = data[pair ? 'createdAt' : 'sentAt'];
      added.add(
        SearchMessage(
          document.id,
          text,
          date is Timestamp ? date.toDate() : DateTime.now(),
          data[pair ? 'from' : 'sender'] == CoupleService.uid,
        ),
      );
    }
    messages.addAll(added);
    scanned += page.docs.length;
    if (page.docs.isNotEmpty) _cursor = page.docs.last;
    done = page.docs.length < 100;
  }
}

class MessageSearchScreen extends StatefulWidget {
  final String source;
  final String? secret;
  final MessageSearchPager? pager;
  const MessageSearchScreen({
    super.key,
    required this.source,
    this.secret,
    this.pager,
  });
  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  late final _pager =
      widget.pager ?? MessageSearchPager(widget.source, secret: widget.secret);
  final _query = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || _pager.done) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _pager.next();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Mesajlar yüklenemedi. Yeniden dene.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = searchText(_query.text.trim());
    final matches = query.isEmpty
        ? <SearchMessage>[]
        : _pager.messages.where((m) => m.searchable.contains(query)).toList();
    return ChatScaffold(
      appBar: AppBar(title: const Text('Mesajlarda ara')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Kelime veya dosya adı ara',
              ),
            ),
          ),
          Text(
            '${_pager.scanned} mesaj tarandı. Kilitli mesajların içeriği aranmaz.',
          ),
          if (_error != null) Text(_error!),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? 'Aramak için bir kelime yaz.'
                          : _busy
                          ? 'Mesajlar taranıyor…'
                          : 'Taranan mesajlarda sonuç bulunamadı.',
                    ),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final message = matches[index];
                      return ListTile(
                        title: Text(
                          message.preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${message.mine ? 'Sen' : 'Karşı taraf'} • ${message.date.day}.${message.date.month}.${message.date.year} ${message.date.hour.toString().padLeft(2, '0')}:${message.date.minute.toString().padLeft(2, '0')}',
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScaffold(
                              starsSource: widget.source,
                              appBar: AppBar(title: const Text('Arama sonucu')),
                              body: SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: MessageContent(text: message.text),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (!_pager.done)
            SafeArea(
              top: false,
              child: TextButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.history),
                label: Text(
                  _error != null
                      ? 'Yeniden dene'
                      : 'Daha eski 100 mesajda da ara',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
