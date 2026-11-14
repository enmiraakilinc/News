// Sohbet listesi ve son mesajları cihazda saklar; internet yokken açılır.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../pair/couple_service.dart';
import 'chat_service.dart';

class ChatOfflineCache {
  static final _memory = <String, String>{};
  static final _timers = <String, Timer>{};

  static Future<File?> _file(String name) async {
    final uid = CoupleService.uid;
    if (uid == null) return null;
    final root = await getApplicationSupportDirectory();
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${root.path}/chat_cache/$uid/$safe.json');
  }

  static Future<Object?> _read(String name) async {
    try {
      final file = await _file(name);
      if (file == null) return null;
      final key = file.path;
      final text =
          _memory[key] ??
          (await file.exists() ? await file.readAsString() : null);
      if (text == null) return null;
      _memory[key] = text;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String name, Object value) async {
    try {
      final file = await _file(name);
      if (file == null) return;
      final text = jsonEncode(value);
      if (_memory[file.path] == text) return;
      _memory[file.path] = text;
      _timers[file.path]?.cancel();
      _timers[file.path] = Timer(const Duration(milliseconds: 800), () async {
        _timers.remove(file.path);
        try {
          await file.parent.create(recursive: true);
          await file.writeAsString(text, flush: true);
        } catch (_) {}
      });
    } catch (_) {}
  }

  static Map<String, int> _times(Map<String, DateTime> value) => {
    for (final e in value.entries) e.key: e.value.millisecondsSinceEpoch,
  };

  static Map<String, DateTime> _dates(Object? value) => {
    if (value is Map)
      for (final e in value.entries)
        if (e.key is String && e.value is int)
          e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
  };

  static Future<List<ChatMessage>?> messages(String chatId) async {
    final raw = await _read('m_$chatId');
    if (raw is! List) return null;
    try {
      return [
        for (final item in raw.whereType<Map>())
          ChatMessage(
            id: item['id'] as String,
            reactions: Map<String, String>.from(item['reactions'] as Map),
            edited: item['edited'] == true,
            sender: item['sender'] as String,
            text: item['text'] as String,
            sentAt: DateTime.fromMillisecondsSinceEpoch(item['sentAt'] as int),
            openAt: DateTime.fromMillisecondsSinceEpoch(item['openAt'] as int),
            readBy: List<String>.from(item['readBy'] as List),
            replyTo: item['replyTo'] as String?,
            scheduled: item['scheduled'] != false,
            readAt: _dates(item['readAt']),
            deliveredAt: _dates(item['deliveredAt']),
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  static void saveMessages(String chatId, List<ChatMessage> list) {
    unawaited(
      _write('m_$chatId', [
        for (final m in list.where((m) => !m.pending).take(200))
          {
            'id': m.id,
            'reactions': m.reactions,
            'edited': m.edited,
            'sender': m.sender,
            'text': m.text,
            'sentAt': m.sentAt.millisecondsSinceEpoch,
            'openAt': m.openAt.millisecondsSinceEpoch,
            'readBy': m.readBy,
            'replyTo': m.replyTo,
            'scheduled': m.scheduled,
            'readAt': _times(m.readAt),
            'deliveredAt': _times(m.deliveredAt),
          },
      ]),
    );
  }

  static Future<List<Conversation>?> conversations() async {
    final raw = await _read('conversations');
    if (raw is! List) return null;
    try {
      return [
        for (final item in raw.whereType<Map>())
          Conversation(
            id: item['id'] as String,
            group: item['group'] == true,
            title: item['title'] as String,
            members: List<String>.from(item['members'] as List),
            names: Map<String, String>.from(item['names'] as Map),
            updatedAt: item['updatedAt'] is int
                ? DateTime.fromMillisecondsSinceEpoch(item['updatedAt'] as int)
                : null,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  static void saveConversations(List<Conversation> list) {
    unawaited(
      _write('conversations', [
        for (final c in list)
          {
            'id': c.id,
            'group': c.group,
            'title': c.title,
            'members': c.members,
            'names': c.names,
            'updatedAt': c.updatedAt?.millisecondsSinceEpoch,
          },
      ]),
    );
  }
}
