// Okunmamış mesaj sayısını tutar.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';
import '../pair/couple_service.dart';
import '../pair/badge_service.dart';

/// The conversation currently on screen. Cleared when the app leaves the foreground
/// so a background message can still notify.
class ActiveConversation {
  static String? sourceKey;
  static final liveRefresh = ValueNotifier<int>(0);
  static Timer? _beat;

  static void noteIncomingMessage() {
    liveRefresh.value = liveRefresh.value + 1;
  }
  static Future<void> set(String? key) async {
    sourceKey = key;
    if (key == null) {
      _beat?.cancel();
      _beat = null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (key == null) {
      await prefs.remove('active_chat_source');
      await prefs.remove('active_chat_at');
    } else {
      await prefs.setString('active_chat_source', key);
      await prefs.setInt('active_chat_at', DateTime.now().millisecondsSinceEpoch);
      _beat ??= Timer.periodic(const Duration(seconds: 8), (_) {
        final current = sourceKey;
        if (current != null) unawaited(set(current));
      });
    }
  }

  static bool matches(String? chatId) {
    final active = sourceKey;
    if (active == null || chatId == null || chatId.isEmpty) return false;
    return active == chatId ||
        active == 'chat/$chatId' ||
        active == 'couple/$chatId';
  }
}

int unreadMessageCount(
  Iterable<ChatMessage> messages, {
  String? userId,
  String? chatId,
}) => messages
    .where(
      (m) =>
          m.sender != (userId ?? CoupleService.uid) &&
          m.unlocked &&
          !m.readBy.contains(userId ?? CoupleService.uid) &&
          (chatId == null || !ChatReadMemory.contains(chatId, m.id)),
    )
    .length;

int? unreadDividerIndex(List<ChatMessage> messages, {String? userId}) {
  final uid = userId ?? CoupleService.uid;
  var oldestUnread = -1;
  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    if (message.sender != uid &&
        message.unlocked &&
        !message.readBy.contains(uid)) {
      oldestUnread = index;
    }
  }
  return oldestUnread < 0 ? null : oldestUnread + 1;
}

class ChatTotalBadge extends StatefulWidget {
  final int baseCount;
  const ChatTotalBadge({super.key, this.baseCount = 0});
  @override
  State<ChatTotalBadge> createState() => _ChatTotalBadgeState();
}

class _ChatTotalBadgeState extends State<ChatTotalBadge> {
  StreamSubscription<List<Conversation>>? _chats;
  final _subscriptions = <String, StreamSubscription<List<ChatMessage>>>{};
  final _latest = <String, List<ChatMessage>>{};
  final _counts = <String, int>{};

  void _recount() {
    for (final entry in _latest.entries) {
      _counts[entry.key] = unreadMessageCount(entry.value, chatId: entry.key);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ChatReadMemory.seen.addListener(_recount);
    unawaited(ChatReadMemory.ensure());
    _chats = ChatService.conversations().listen((chats) {
      final ids = chats.map((chat) => chat.id).toSet();
      for (final id
          in _subscriptions.keys.where((id) => !ids.contains(id)).toList()) {
        _subscriptions.remove(id)?.cancel();
        _counts.remove(id);
        _latest.remove(id);
      }
      for (final id in ids) {
        _subscriptions.putIfAbsent(
          id,
          () => ChatService.messages(id).listen((messages) {
            _latest[id] = messages;
            _recount();
          }, onError: (Object _) {}),
        );
      }
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    ChatReadMemory.seen.removeListener(_recount);
    _chats?.cancel();
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YeniRozet(
    widget.baseCount +
        _counts.values.fold<int>(0, (total, value) => total + value),
  );
}

class ChatUnreadBadge extends StatefulWidget {
  final String chatId;
  const ChatUnreadBadge({super.key, required this.chatId});
  @override
  State<ChatUnreadBadge> createState() => _ChatUnreadBadgeState();
}

class _ChatUnreadBadgeState extends State<ChatUnreadBadge> {
  late Stream<List<ChatMessage>> _stream = ChatService.messages(widget.chatId);
  @override
  void didUpdateWidget(covariant ChatUnreadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _stream = ChatService.messages(widget.chatId);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ChatMessage>>(
    stream: _stream,
    builder: (_, snapshot) =>
        YeniRozet(unreadMessageCount(snapshot.data ?? [])),
  );
}
