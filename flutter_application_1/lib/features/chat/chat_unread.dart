import 'dart:async';
import 'package:flutter/material.dart';
import 'chat_service.dart';
import '../pair/couple_service.dart';
import '../pair/badge_service.dart';

int unreadMessageCount(Iterable<ChatMessage> messages, {String? userId}) =>
    messages
        .where(
          (m) =>
              m.sender != (userId ?? CoupleService.uid) &&
              m.unlocked &&
              !m.readBy.contains(userId ?? CoupleService.uid),
        )
        .length;

class ChatTotalBadge extends StatefulWidget {
  final int baseCount;
  const ChatTotalBadge({super.key, this.baseCount = 0});
  @override
  State<ChatTotalBadge> createState() => _ChatTotalBadgeState();
}

class _ChatTotalBadgeState extends State<ChatTotalBadge> {
  StreamSubscription<List<Conversation>>? _chats;
  final _subscriptions = <String, StreamSubscription<List<ChatMessage>>>{};
  final _counts = <String, int>{};
  @override
  void initState() {
    super.initState();
    _chats = ChatService.conversations().listen((chats) {
      final ids = chats.map((chat) => chat.id).toSet();
      for (final id
          in _subscriptions.keys.where((id) => !ids.contains(id)).toList()) {
        _subscriptions.remove(id)?.cancel();
        _counts.remove(id);
      }
      for (final id in ids) {
        _subscriptions.putIfAbsent(
          id,
          () => ChatService.messages(id).listen((messages) {
            if (mounted) {
              setState(() => _counts[id] = unreadMessageCount(messages));
            }
          }, onError: (Object _) {}),
        );
      }
      if (mounted) setState(() {});
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
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
