import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'chat_media.dart';

/// One metadata subscription per conversation, not one stream per attachment.
class MediaExpiryScope extends StatefulWidget {
  final String source;
  final Widget child;
  final Stream<Map<String, DateTime>>? dates;
  const MediaExpiryScope({
    super.key,
    required this.source,
    required this.child,
    this.dates,
  });
  @override
  State<MediaExpiryScope> createState() => _MediaExpiryScopeState();
}

class _MediaExpiryScopeState extends State<MediaExpiryScope> {
  late final Stream<Map<String, DateTime>>? _stream;
  @override
  void initState() {
    super.initState();
    final parts = widget.source.split('/');
    try {
      _stream =
          widget.dates ??
          FirebaseFirestore.instance
              .collection('chatMedia')
              .where(
                parts.first == 'chat' ? 'chatId' : 'coupleId',
                isEqualTo: parts.last,
              )
              .orderBy('createdAt', descending: true)
              .limit(500)
              .snapshots()
              .map(
                (snapshot) => {
                  for (final doc in snapshot.docs)
                    if (doc.data()['createdAt'] is Timestamp)
                      doc.id: chatMediaExpiresAt(doc.data()),
                },
              );
    } catch (_) {
      _stream = null;
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, DateTime>>(
    stream: _stream,
    builder: (context, snapshot) => _MediaExpiryData(
      loaded: snapshot.hasData,
      dates: snapshot.data ?? {},
      child: widget.child,
    ),
  );
}

class _MediaExpiryData extends InheritedWidget {
  final bool loaded;
  final Map<String, DateTime> dates;
  const _MediaExpiryData({
    required this.loaded,
    required this.dates,
    required super.child,
  });
  @override
  bool updateShouldNotify(_MediaExpiryData oldWidget) => true;
}

class MediaExpiryLabel extends StatelessWidget {
  final String message;
  final Color color;
  const MediaExpiryLabel({
    super.key,
    required this.message,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    if (!message.startsWith(mediaPrefix)) return const SizedBox.shrink();
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MediaExpiryData>();
    if (scope?.loaded != true) return const SizedBox.shrink();
    String id;
    try {
      id = ChatMedia.idFrom(message);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final date = scope!.dates[id];
    final text = date == null
        ? 'Süre bilgisi alınamadı'
        : !date.isAfter(DateTime.now())
        ? 'Erişim süresi doldu'
        : 'Erişim: ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
