// Son görülme zamanını yazar ve okur.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show FirebaseFirestorePlatform;
import '../../core/data/oracle_firestore_bridge.dart';

class ChatPresence {
  static final changes = ValueNotifier<int>(0);
  static final activity = ValueNotifier<String?>(null);
  static int _sessions = 0;
  static Future<void> _recordQueue = Future<void>.value();

  static Future<void> recordQueued({required bool online, String? game}) {
    final next = _recordQueue
        .catchError((Object _) {})
        .then((_) => record(online: online, game: game));
    _recordQueue = next;
    return next;
  }

  static void setActivity(String? game) {
    if (game != null &&
        !const {'Sudoku', '15 Taş', 'Block Blast'}.contains(game)) {
      throw ArgumentError.value(game, 'game', 'Oyun etkinliği geçersiz.');
    }
    activity.value = game;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_sessions == 0 &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      unawaited(
        recordQueued(online: true, game: game).catchError((Object error) {
          debugPrint('Chat game presence update failed: $error');
        }),
      );
    }
  }

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

  static Future<void> record({required bool online, String? game}) async {
    final uid = CoupleService.uid;
    final platform = FirebaseFirestorePlatform.instance;
    if (uid != null && platform is OracleFirestoreBridge && platform.primary) {
      await platform.primaryTransport.post('/presence', {
        'online': online,
        'game': online ? game : null,
      }, timeout: const Duration(seconds: 5));
      return;
    }
    if (uid == null || CoupleService.uid != uid) return;
    final status = ref(uid);
    final data = (await status.get(
      const GetOptions(source: Source.server),
    )).data();
    if (data?['enabled'] != true) return;
    await status.update({
      'online': online,
      'lastSeenAt': FieldValue.serverTimestamp(),
      'game': online && game != null ? game : FieldValue.delete(),
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
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    ChatPresence._sessions++;
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    ChatPresence.changes.addListener(_refresh);
    ChatPresence.activity.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    _timer?.cancel();
    if (!_foreground) return;
    unawaited(_record(online: true));
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_record(online: true)),
    );
  }

  Future<void> _record({required bool online}) async {
    try {
      await ChatPresence.recordQueued(
        online: online,
        game: online ? ChatPresence.activity.value : null,
      );
    } catch (error) {
      debugPrint('Chat presence update failed: $error');
    }
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
    ChatPresence.activity.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    ChatPresence._sessions--;
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
  DateTime? _seenAt;
  bool _online = false;
  String? _peerId;
  @override
  void initState() {
    super.initState();
    ChatPresence.changes.addListener(_onPresence);
    _listen();
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LastSeenLabel old) {
    super.didUpdateWidget(old);
    if (old.peer != widget.peer || old.source != widget.source) {
      _listen(notify: true);
    }
  }

  void _listen({bool notify = false}) {
    final peer = widget.peer;
    _peerId = peer;
    try {
      _stream = peer == null ? null : ChatPresence.ref(peer).snapshots();
    } catch (_) {
      _stream = null;
    }
    if (peer == null && widget.source.startsWith('couple/')) {
      unawaited(_pairPeer());
    } else if (peer != null) {
      unawaited(_refreshFromServer(peer));
    }
    if (notify && mounted) setState(() {});
  }

  void _onPresence() {
    final peer = _peerId ?? widget.peer;
    if (peer != null) unawaited(_refreshFromServer(peer));
  }

  Future<void> _refreshFromServer(String peer) async {
    try {
      final data = (await ChatPresence.ref(
        peer,
      ).get(const GetOptions(source: Source.server))).data();
      if (!mounted || _peerId != peer) return;
      _apply(data);
      setState(() {});
    } catch (_) {}
  }

  void _apply(Map<String, dynamic>? data) {
    if (data == null || data['enabled'] != true) return;
    final next = presenceInstant(data['lastSeenAt']);
    if (next != null && (_seenAt == null || !next.isBefore(_seenAt!))) {
      _seenAt = next;
      _online = data['online'] == true;
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
        final peer = peers.single;
        setState(() {
          _peerId = peer;
          _stream = ChatPresence.ref(peer).snapshots();
        });
        await _refreshFromServer(peer);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _clock?.cancel();
    ChatPresence.changes.removeListener(_onPresence);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _stream,
    builder: (context, snapshot) {
      _apply(snapshot.data?.data());
      final now = DateTime.now();
      final date = _seenAt;
      final online = _online && isPresenceOnline(date, now: now);
      final game = online ? (snapshot.data?.data()?['game'] as String?) : null;
      final text = online
          ? game == null
                ? 'Çevrimiçi'
                : '$game oynuyor'
          : formatLastSeen(date, now: now) ?? widget.fallback;
      return Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
        ),
      );
    },
  );
}

String? formatLastSeen(DateTime? date, {DateTime? now}) {
  if (date == null) return null;
  final current = now ?? DateTime.now();
  final local = date.isUtc ? date.toLocal() : date;
  final age = current.difference(local);
  if (age.isNegative) return null;
  if (age < const Duration(minutes: 2)) return 'Az önce';
  if (age < const Duration(hours: 1)) return '${age.inMinutes} dk önce';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (DateUtils.isSameDay(local, current)) return 'Bugün $time';
  if (DateUtils.isSameDay(local, current.subtract(const Duration(days: 1)))) {
    return 'Dün $time';
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return local.year == current.year
      ? '$day.$month $time'
      : '$day.$month.${local.year} $time';
}

DateTime? presenceInstant(Object? stamp) {
  if (stamp is Timestamp) {
    final date = stamp.toDate();
    return date.isUtc ? date.toLocal() : date;
  }
  if (stamp is DateTime) return stamp.isUtc ? stamp.toLocal() : stamp;
  if (stamp is String) {
    final parsed = DateTime.tryParse(stamp);
    if (parsed == null) return null;
    return parsed.toLocal();
  }
  if (stamp is int) {
    final millis = stamp.abs() > 100000000000 ? stamp : stamp * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  return null;
}

bool isPresenceOnline(DateTime? date, {DateTime? now}) {
  if (date == null) return false;
  final local = date.isUtc ? date.toLocal() : date;
  final age = (now ?? DateTime.now()).difference(local);
  return !age.isNegative && age < const Duration(seconds: 45);
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
            } on TimeoutException {
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
