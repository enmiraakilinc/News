import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show FirebaseFirestorePlatform;
import '../../core/data/oracle_firestore_bridge.dart';

class ChatPresence {
  static final changes = ValueNotifier<int>(0);
  static DocumentReference<Map<String, dynamic>> ref(String uid) =>
      FirebaseFirestore.instance.doc('chatAccounts/$uid/presence/status');
  static Future<bool> enabled() async {
    final uid = CoupleService.uid;
    if (uid == null) return false;
    try {
      return (await ref(
            uid,
          ).get(const GetOptions(source: Source.server))).data()?['enabled'] ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> record({required bool online}) async {
    final uid = CoupleService.uid;
    final platform = FirebaseFirestorePlatform.instance;
    if (uid != null && platform is OracleFirestoreBridge && platform.primary) {
      await platform.primaryTransport.post(
        '/presence',
        {'online': online},
        timeout: const Duration(seconds: 5),
      );
      return;
    }
    if (uid == null || CoupleService.uid != uid) return;
    final status = ref(uid);
    final data = (await status.get(const GetOptions(source: Source.server))).data();
    if (data?['enabled'] != true) return;
    await status.update({
      'online': online,
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  static DocumentReference<Map<String, dynamic>> preferences(String uid) =>
      FirebaseFirestore.instance.doc(
        'chatAccounts/$uid/personalConfig/presence',
      );
  static Future<Set<String>> sharedPeers() async {
    final uid = CoupleService.uid;
    if (uid == null) return {};
    final data = (await preferences(
      uid,
    ).get(const GetOptions(source: Source.server))).data();
    return (data?['peers'] as List? ?? []).whereType<String>().toSet();
  }

  static Future<List<String>> peersFor(String source, String? peer) async {
    final uid = CoupleService.uid;
    if (uid == null) return [];
    if (peer != null) return peer == uid ? [] : [peer];
    final p = source.split('/');
    final data =
        (await FirebaseFirestore.instance
                .doc('${p.first == 'chat' ? 'chats' : 'couples'}/${p.last}')
                .get())
            .data();
    return (data?['members'] as List? ?? [])
        .whereType<String>()
        .where((v) => v != uid)
        .toList();
  }

  static Future<void> setSharedWith(List<String> peers, bool value) async {
    final uid = CoupleService.uid;
    if (uid == null) throw Exception('Hesabına giriş yap.');
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final config = preferences(uid), status = ref(uid);
      final data = (await tx.get(config)).data();
      final allowed = (data?['peers'] as List? ?? [])
          .whereType<String>()
          .toSet();
      if (value) {
        allowed.addAll(peers);
      } else {
        allowed.removeAll(peers);
      }
      tx.set(config, {'peers': allowed.toList()..sort()});
      tx.set(status, {
        'enabled': allowed.isNotEmpty,
        'online': false,
        if (allowed.isNotEmpty) 'lastSeenAt': FieldValue.serverTimestamp(),
      });
    });
    changes.value++;
  }
}

/// Only foreground chat activity is recorded; no background tracking/service.
class ChatPresenceSession extends StatefulWidget {
  final Widget child;
  const ChatPresenceSession({super.key, required this.child});
  @override
  State<ChatPresenceSession> createState() => _ChatPresenceSessionState();
}

class _ChatPresenceSessionState extends State<ChatPresenceSession>
    with WidgetsBindingObserver {
  Timer? _timer;
  Future<void> _presenceQueue = Future<void>.value();
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ChatPresence.changes.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    _timer?.cancel();
    if (!_foreground) return;
    unawaited(_record(online: true));
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_record(online: true)),
    );
  }

  Future<void> _record({required bool online}) async {
    _presenceQueue = _presenceQueue.then((_) async {
      try {
        await ChatPresence.record(online: online);
      } catch (error) {
        debugPrint('Chat presence update failed: $error');
      }
    });
    await _presenceQueue;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_record(online: false));
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ChatPresence.changes.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_record(online: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class LastSeenLabel extends StatefulWidget {
  final String? peer;
  final String fallback;
  final String source;
  const LastSeenLabel({
    super.key,
    this.peer,
    required this.fallback,
    required this.source,
  });
  @override
  State<LastSeenLabel> createState() => _LastSeenLabelState();
}

class _LastSeenLabelState extends State<LastSeenLabel> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LastSeenLabel old) {
    super.didUpdateWidget(old);
    if (old.peer != widget.peer || old.source != widget.source) _listen();
  }

  void _listen() {
    try {
      _stream = widget.peer == null
          ? null
          : ChatPresence.ref(widget.peer!).snapshots();
    } catch (_) {
      _stream = null;
    }
    if (widget.peer == null && widget.source.startsWith('couple/')) {
      unawaited(_pairPeer());
    }
  }

  Future<void> _pairPeer() async {
    final source = widget.source;
    try {
      final data =
          (await FirebaseFirestore.instance
                  .doc('couples/${source.split('/').last}')
                  .get())
              .data();
      final peers = (data?['members'] as List? ?? [])
          .whereType<String>()
          .where((uid) => uid != CoupleService.uid)
          .toList();
      if (mounted && widget.source == source && peers.length == 1) {
        setState(() => _stream = ChatPresence.ref(peers.single).snapshots());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final stamp = (data?['enabled'] == true) ? data!['lastSeenAt'] : null;
          final date = stamp is Timestamp ? stamp.toDate().toLocal() : null;
          final now = DateTime.now();
          final online =
              data?['online'] == true && isPresenceOnline(date, now: now);
          final text = online
              ? 'Çevrimiçi'
              : formatLastSeen(date, now: now) ?? widget.fallback;
          return Tooltip(
            message: text,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          );
        },
      );
}

String? formatLastSeen(DateTime? date, {DateTime? now}) {
  if (date == null) return null;
  final current = now ?? DateTime.now();
  final age = current.difference(date);
  if (!age.isNegative && age < const Duration(minutes: 2)) return 'Az önce';
  if (!age.isNegative && age < const Duration(hours: 1)) {
    return '${age.inMinutes} dk önce';
  }
  final time =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (DateUtils.isSameDay(date, current)) return 'Bugün $time';
  if (DateUtils.isSameDay(date, current.subtract(const Duration(days: 1)))) {
    return 'Dün $time';
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return date.year == current.year
      ? '$day.$month $time'
      : '$day.$month.${date.year} $time';
}

bool isPresenceOnline(DateTime? date, {DateTime? now}) {
  if (date == null) return false;
  final age = (now ?? DateTime.now()).difference(date);
  return !age.isNegative && age < const Duration(seconds: 90);
}

class ChatTypingLabel extends StatelessWidget {
  final String? chatId;
  final Map<String, String>? members;
  final Widget fallback;
  const ChatTypingLabel({
    super.key,
    required this.chatId,
    required this.fallback,
    this.members,
  });

  @override
  Widget build(BuildContext context) {
    if (chatId == null) return fallback;
    return _ChatTypingLabel(
      chatId: chatId!,
      members: members,
      fallback: fallback,
    );
  }
}

class _ChatTypingLabel extends StatefulWidget {
  final String chatId;
  final Map<String, String>? members;
  final Widget fallback;
  const _ChatTypingLabel({
    required this.chatId,
    required this.members,
    required this.fallback,
  });

  @override
  State<_ChatTypingLabel> createState() => _ChatTypingLabelState();
}

class _ChatTypingLabelState extends State<_ChatTypingLabel> {
  Timer? _clock;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _ChatTypingLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) _listen();
  }

  void _listen() {
    try {
      _stream = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('typing')
          .where('typing', isEqualTo: true)
          .snapshots();
    } catch (_) {
      _stream = null;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final now = DateTime.now();
          final typing = (snapshot.data?.docs ?? [])
              .where((document) {
                if (document.id == CoupleService.uid) return false;
                final stamp = document.data()['updatedAt'];
                if (stamp is! Timestamp) return false;
                final age = now.difference(stamp.toDate());
                return !age.isNegative && age < const Duration(seconds: 8);
              })
              .map((document) => document.id)
              .toList();
          if (typing.isEmpty) return widget.fallback;
          return const _BlinkingTypingLabel();
        },
      );
}

class _BlinkingTypingLabel extends StatefulWidget {
  const _BlinkingTypingLabel();

  @override
  State<_BlinkingTypingLabel> createState() => _BlinkingTypingLabelState();
}

class _BlinkingTypingLabelState extends State<_BlinkingTypingLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.45,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: Text(
      'Yazıyor...',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class LastSeenSwitch extends StatefulWidget {
  final String source;
  final String? peer;
  const LastSeenSwitch({super.key, required this.source, this.peer});
  @override
  State<LastSeenSwitch> createState() => _LastSeenSwitchState();
}

class _LastSeenSwitchState extends State<LastSeenSwitch> {
  bool _enabled = false, _busy = true;
  List<String> _peers = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final peers = await ChatPresence.peersFor(widget.source, widget.peer);
      final allowed = await ChatPresence.sharedPeers();
      if (mounted) {
        setState(() {
          _peers = peers;
          _enabled = peers.isNotEmpty && peers.every(allowed.contains);
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Son görülmemi paylaş'),
    subtitle: const Text('Bu kişiyle paylaşılır. Kapalıyken bu kişi göremez.'),
    value: _enabled,
    onChanged: _busy || _peers.isEmpty
        ? null
        : (v) async {
            setState(() => _busy = true);
            try {
              await ChatPresence.setSharedWith(_peers, v);
              if (mounted) setState(() => _enabled = v);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Son görülme ayarı kaydedilemedi.'),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
