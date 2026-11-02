import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../chat/chat_service.dart';
import '../pair/couple_service.dart';
import 'chat_media.dart';
import 'media_expiry_scope.dart';
import 'message_content.dart';

class SharedConversationMediaScreen extends StatefulWidget {
  final String sourceKey;
  const SharedConversationMediaScreen({super.key, required this.sourceKey});

  @override
  State<SharedConversationMediaScreen> createState() =>
      _SharedConversationMediaScreenState();
}

class _SharedConversationMediaScreenState
    extends State<SharedConversationMediaScreen> {
  late final Stream<List<_SharedMediaMessage>> _messages = _watchMessages();
  String? _signature;
  Future<_AvailableMedia> _available = Future.value(
    const _AvailableMedia([], 0),
  );

  Stream<List<_SharedMediaMessage>> _watchMessages() async* {
    await CoupleService.ensureReady();
    final parts = widget.sourceKey.split('/');
    if (parts.length != 2 || !['chat', 'couple'].contains(parts.first)) {
      throw const FormatException('Geçersiz sohbet.');
    }
    if (parts.first == 'couple') {
      if (await CoupleService.coupleId() != parts[1]) {
        throw StateError('Bu mektup sohbetine erişilemiyor.');
      }
      final secret = await CoupleService.secret();
      if (secret == null) {
        throw StateError(
          'Mektup medyalarını görmek için gizli kelime gerekli.',
        );
      }
      await for (final letters in CoupleService.lettersStream(
        parts[1],
        secret,
        limit: 500,
      )) {
        yield [
          for (final letter in letters)
            if (letter.text != null)
              _SharedMediaMessage(letter.id, letter.text!, letter.sentDate),
        ];
      }
      return;
    }
    await for (final messages in ChatService.messages(parts[1], limit: 500)) {
      yield [
        for (final message in messages)
          _SharedMediaMessage(message.id, message.text, message.sentAt),
      ];
    }
  }

  Future<_AvailableMedia> _loadAvailable(
    List<_SharedMediaMessage> messages,
  ) async {
    final available = <_SharedMediaMessage>[];
    var unavailable = 0;
    final remoteMessages = messages
        .where((message) => message.text.startsWith(mediaPrefix))
        .toList();
    final byId = <String, Map<String, dynamic>>{};
    if (remoteMessages.isNotEmpty) {
      final parts = widget.sourceKey.split('/');
      final field = parts.first == 'chat' ? 'chatId' : 'coupleId';
      final metadata = await FirebaseFirestore.instance
          .collection('chatMedia')
          .where(field, isEqualTo: parts[1])
          .limit(500)
          .get(const GetOptions(source: Source.server));
      byId.addEntries(
        metadata.docs.map((document) => MapEntry(document.id, document.data())),
      );
    }
    for (final message in messages) {
      if (message.text.startsWith(attachmentPrefix)) {
        available.add(message);
      } else if (message.text.startsWith(mediaPrefix)) {
        try {
          final data = byId[ChatMedia.idFrom(message.text)];
          if (data == null) {
            unavailable++;
            continue;
          }
          if (data['ready'] == true &&
              chatMediaExpiresAt(data).isAfter(DateTime.now())) {
            available.add(message);
          } else {
            unavailable++;
          }
        } catch (_) {
          unavailable++;
        }
      }
    }
    return _AvailableMedia(available, unavailable);
  }

  @override
  Widget build(BuildContext context) => MediaExpiryScope(
    source: widget.sourceKey,
    child: Scaffold(
      appBar: AppBar(title: const Text('Medya, bağlantılar ve belgeler')),
      body: StreamBuilder<List<_SharedMediaMessage>>(
        stream: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Medya listesi yüklenemedi.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final media = snapshot.data!
              .where(
                (message) =>
                    message.text.startsWith(mediaPrefix) ||
                    message.text.startsWith(attachmentPrefix),
              )
              .toList();
          final signature = media.map((message) => message.id).join(',');
          if (_signature != signature) {
            _signature = signature;
            _available = _loadAvailable(media);
          }
          return FutureBuilder<_AvailableMedia>(
            future: _available,
            builder: (context, result) {
              if (result.hasError) {
                return const Center(
                  child: Text('Medya erişim bilgileri yüklenemedi.'),
                );
              }
              if (!result.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = result.data!;
              if (items.messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      media.isEmpty
                          ? 'Bu sohbette henüz medya veya belge yok.'
                          : 'Şu anda erişilebilen medya veya belge bulunmuyor.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final photoMessages = [
                for (final message in items.messages.reversed) message.text,
              ];
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount:
                    items.messages.length + (items.unavailable > 0 ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == items.messages.length) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${items.unavailable} öğenin erişim süresi dolmuş veya dosyası artık sunucuda değil.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final message = items.messages[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            messagePreview(message.text),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (message.sentAt != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${message.sentAt!.day.toString().padLeft(2, '0')}.'
                                '${message.sentAt!.month.toString().padLeft(2, '0')}.'
                                '${message.sentAt!.year}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          const SizedBox(height: 8),
                          MessageContent(
                            text: message.text,
                            photoMessages: photoMessages,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    ),
  );
}

class _AvailableMedia {
  final List<_SharedMediaMessage> messages;
  final int unavailable;
  const _AvailableMedia(this.messages, this.unavailable);
}

class _SharedMediaMessage {
  final String id;
  final String text;
  final DateTime? sentAt;
  const _SharedMediaMessage(this.id, this.text, this.sentAt);
}
