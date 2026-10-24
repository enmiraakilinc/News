import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../pair/couple_service.dart';
import '../contacts/contact_names.dart';
import '../../core/utils/user_errors.dart';
import 'call_background.dart';
import 'call_controls.dart';
import 'call_audio.dart';
import 'call_ringtone.dart';
import '../../core/security/feature_access.dart';
import '../../core/notifications/incoming_call_settings.dart';
import '../../core/security/secure_screen.dart';

const voiceCallRingDuration = Duration(seconds: 45);
Duration voiceCallElapsed(DateTime started, DateTime now) {
  final elapsed = now.difference(started);
  return elapsed.isNegative ? Duration.zero : elapsed;
}

class VoiceCalls {
  static final answerRequested = ValueNotifier<String?>(null);
  static bool active = false;
  static CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance.collection('voiceCalls');
  static Future<bool> enabled() async {
    try {
      return (await FirebaseFirestore.instance
                  .doc('config/voice_calls')
                  .get(const GetOptions(source: Source.server)))
              .data()?['enabled'] ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> start(
    BuildContext context,
    String source,
    String name, {
    bool video = false,
  }) async {
    if (active) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await FeatureAccess.require('calls');
      await FeatureAccess.require('microphone');
      if (video) await FeatureAccess.require('camera');
      await CoupleService.ensureReady();
      if (!await enabled()) {
        throw Exception('Sesli arama bu sürüm için henüz etkinleştirilmedi.');
      }
      final parts = source.split('/');
      final data =
          (await FirebaseFirestore.instance
                  .collection(parts[0] == 'chat' ? 'chats' : 'couples')
                  .doc(parts[1])
                  .get(const GetOptions(source: Source.server)))
              .data();
      final members = List<String>.from(data?['members'] ?? []);
      if (members.length != 2 || !members.contains(CoupleService.uid)) {
        throw Exception('Yalnızca birebir sohbetlerde arayabilirsin.');
      }
      if (!context.mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${video ? 'Görüntülü' : 'Sesli'} arama · S?re s?n?r? yok',
          ),
          content: const Text(
            'Karşı taraf Ayarlar’dan uygulama kapalıyken arama almayı açabilir. Görüşme bildirim izniyle arka planda sürer. Ses kaydı tutulmaz. Bağlantı için Google STUN sunucusuyla ağ adresi bilgisi paylaşılır; farklı ağlarda bağlantı kurulamayabilir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ara'),
            ),
          ],
        ),
      );
      if (accepted != true || !context.mounted || active) return;
      active = true;
      try {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => VoiceCallScreen(
              reference: collection.doc(),
              source: source,
              peer: members.firstWhere((id) => id != CoupleService.uid),
              name: name,
              video: video,
            ),
          ),
        );
      } finally {
        active = false;
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }
}

class VoiceCallInbox extends StatefulWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  final Future<void> Function()? bootstrap;
  const VoiceCallInbox({
    super.key,
    required this.navigator,
    required this.child,
    this.bootstrap,
  });
  @override
  State<VoiceCallInbox> createState() => _VoiceCallInboxState();
}

class _VoiceCallInboxState extends State<VoiceCallInbox>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _auth;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _incoming;
  StreamSubscription<NativeCallEvent>? _native;
  final _seen = <String>{};
  bool _foreground = true;
  int _authGeneration = 0;
  bool _initializing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await (widget.bootstrap?.call() ?? CoupleService.ensureReady());
      if (!mounted) return;
      CallBackground.initialize();
      await _native?.cancel();
      _native = CallBackground.events.stream.listen((event) {
        if (event.method == 'answer') {
          _fromNotification(event.id).catchError((_) {});
        }
      });
      unawaited(CallBackground.restore().catchError((_) {}));
      final pending = await CallBackground.channel
          .invokeMethod<String>('consumePending')
          .catchError((_) => null);
      if (pending != null) _fromNotification(pending).catchError((_) {});
      _auth = FirebaseAuth.instance.authStateChanges().listen((user) async {
        final generation = ++_authGeneration;
        await _incoming?.cancel();
        _seen.clear();
        if (!mounted || user == null || generation != _authGeneration) return;
        _incoming = VoiceCalls.collection
            .where('callee', isEqualTo: user.uid)
            .snapshots()
            .listen((snapshot) {
              for (final doc in snapshot.docs) {
                _receive(doc, user.uid).catchError((_) {});
              }
            }, onError: (_) {});
      });
    } catch (_) {
    } finally {
      _initializing = false;
    }
  }

  Future<void> _receive(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) async {
    if (!await FeatureAccess.enabled('calls') ||
        !await FeatureAccess.enabled('microphone') ||
        !mounted) {
      return;
    }
    final data = doc.data();
    if (data == null) return;
    if (!await incomingCallsEnabled(video: data['video'] == true)) return;
    final created = data['createdAt'];
    if (!_foreground ||
        data['state'] != 'ringing' ||
        created is! Timestamp ||
        DateTime.now().difference(created.toDate()) > voiceCallRingDuration ||
        !_seen.add(doc.id)) {
      return;
    }
    if (_seen.length > 100) _seen.remove(_seen.first);
    if (VoiceCalls.active) {
      await doc.reference
          .update({'state': 'ended', 'endedAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
      return;
    }
    final source = data['sourceKey'] as String;
    if (source.startsWith('couple/') &&
        (await CoupleService.coupleId() != source.split('/')[1] ||
            await CoupleService.secret() == null)) {
      return;
    }
    if (!mounted ||
        FirebaseAuth.instance.currentUser?.uid != uid ||
        !_foreground ||
        VoiceCalls.active) {
      return;
    }
    final nav = widget.navigator.currentState;
    if (nav == null) {
      _seen.remove(doc.id);
      return;
    }
    VoiceCalls.active = true;
    try {
      await nav.push<void>(
        MaterialPageRoute(
          builder: (_) => VoiceCallScreen(
            reference: doc.reference,
            source: source,
            peer: data['caller'] as String,
            name: ContactNames.name(
              source.startsWith('couple/')
                  ? ContactNames.posniId
                  : source.split('/')[1],
              'Gelen sesli arama',
            ),
            incoming: true,
            video: data['video'] == true,
          ),
        ),
      );
    } finally {
      VoiceCalls.active = false;
    }
  }

  Future<void> _fromNotification(String id) async {
    if (!RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id) || !mounted) return;
    VoiceCalls.answerRequested.value = id;
    if (VoiceCalls.active) return;
    final uid = CoupleService.uid;
    if (uid == null) return;
    final doc = await VoiceCalls.collection
        .doc(id)
        .get(const GetOptions(source: Source.server));
    if (doc.data()?['callee'] != uid) return;
    _seen.remove(id);
    await _receive(doc, uid);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _auth == null) {
      _initialize();
      return;
    }
    if (_foreground) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        VoiceCalls.collection
            .where('callee', isEqualTo: uid)
            .get()
            .then((snapshot) {
              for (final doc in snapshot.docs) {
                _receive(doc, uid).catchError((_) {});
              }
            })
            .catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    _incoming?.cancel();
    _native?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class VoiceCallScreen extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> reference;
  final String source, peer, name;
  final bool incoming;
  final bool video;
  const VoiceCallScreen({
    super.key,
    required this.reference,
    required this.source,
    required this.peer,
    required this.name,
    this.incoming = false,
    this.video = false,
  });
  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with WidgetsBindingObserver {
  RTCPeerConnection? _peer;
  MediaStream? _microphone;
  final _localVideo = RTCVideoRenderer();
  final _remoteVideo = RTCVideoRenderer();
  Future<void>? _videoSetup;
  bool _renderersReady = false, _videoDisposed = false, _cameraOff = false;
  bool _disposing = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _signaling;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ice;
  final _remoteCandidates = <RTCIceCandidate>[];
  final _localCandidates = <RTCIceCandidate>[];
  final _seenCandidates = <String>{};
  Timer? _ticker;
  DateTime? _started;
  final _elapsed = Stopwatch();

  late bool _speakerOn = widget.video;
  bool _receiveMuted = false, _audioBusy = false;
  final _remoteAudioTracks = <String, MediaStreamTrack>{};
  bool _readyToSend = false,
      _remoteSet = false,
      _busy = false,
      _closing = false,
      _ended = false,
      _muted = false,
      _connected = false;
  Future<void>? _remoteDescription;
  String _status = 'Aranıyor…';
  final _uid = CoupleService.uid;
  bool _backgroundStarted = false;
  StreamSubscription<NativeCallEvent>? _native;
  DateTime _ringUntil = DateTime.now().add(voiceCallRingDuration);
  CollectionReference<Map<String, dynamic>> get _candidates =>
      widget.reference.collection('candidates');
  @override
  void initState() {
    super.initState();
    SecureScreen.enable();
    WidgetsBinding.instance.addObserver(this);
    if (widget.incoming) {
      _status = widget.video ? 'Gelen görüntülü arama' : 'Gelen sesli arama';
      _ringIncoming();
    }
    CallBackground.initialize();
    _native = CallBackground.events.stream.listen((event) {
      if (event.id == widget.reference.id &&
          ['stop', 'stopped', 'timeout'].contains(event.method)) {
        _finish('Arama sona erdi.');
      }
    });
    VoiceCalls.answerRequested.addListener(_answerFromNotification);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _answerFromNotification(),
    );
    _signaling = widget.reference.snapshots().listen((doc) {
      _changed(doc).catchError(_fail);
    }, onError: _fail);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ended || _closing) return;
      if (FirebaseAuth.instance.currentUser?.uid != _uid) {
        _finish('Hesabın değiştiği için arama sona erdi.');
        return;
      }
      if (_started == null && DateTime.now().isAfter(_ringUntil)) {
        _finish('Yanıt alınamadı.');
      } else if (mounted) {
        setState(() {});
      }
    });
    if (!widget.incoming) _begin();
  }

  Future<void> _ringIncoming() async {
    await CallBackground.cancelIncoming(widget.reference.id);
    if (!mounted || _busy || _closing || _ended || _started != null) return;
    await CallRingtone.ring(widget.reference.id).catchError((_) {});
  }

  void _answerFromNotification() {
    if (widget.incoming &&
        VoiceCalls.answerRequested.value == widget.reference.id &&
        !_ended &&
        !_closing) {
      VoiceCalls.answerRequested.value = null;
      _accept();
    }
  }

  Future<void> _prepare() async {
    if (_closing || _ended) return;
    await FeatureAccess.require('calls');
    await FeatureAccess.require('microphone');
    if (_closing || _ended) return;
    if (widget.video) {
      await FeatureAccess.require('camera');
      if (_closing || _ended) return;
      _videoSetup = () async {
        await _localVideo.initialize();
        await _remoteVideo.initialize();
      }();
      await _videoSetup;
      if (_closing || _ended) {
        await _release();
        return;
      }
      _renderersReady = true;
    }
    if (Platform.isAndroid) {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
    }
    if (_closing || _ended) return;
    _microphone = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 15, 'max': 20},
            }
          : false,
    });
    if (_closing || _ended) {
      await _release();
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      await Helper.setSpeakerphoneOn(_speakerOn);
    }
    if (widget.video) {
      _localVideo.srcObject = _microphone;
      if (mounted) setState(() {});
    }
    _backgroundStarted = await CallBackground.start(
      widget.reference.id,
      video: widget.video,
    );
    if (_closing || _ended) {
      await _release();
      return;
    }
    _peer = await createPeerConnection({
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302'],
        },
      ],
      'sdpSemantics': 'unified-plan',
    });
    if (_closing || _ended) {
      await _release();
      return;
    }
    for (final track in _microphone!.getAudioTracks()) {
      await _peer!.addTrack(track, _microphone!);
    }
    for (final track in _microphone!.getVideoTracks()) {
      await _peer!.addTrack(track, _microphone!);
    }
    _peer!.onTrack = (event) {
      if (_closing || _ended) return;
      if (event.track.kind == 'audio') {
        _remoteAudioTracks[event.track.id!] = event.track;
        setCallReceiveMuted([
          event.track,
        ], _receiveMuted).catchError(_audioError);
      }
      if (widget.video && event.streams.isNotEmpty) {
        _remoteVideo.srcObject = event.streams.first;
        if (mounted) setState(() {});
      }
    };
    _peer!.onIceCandidate = (candidate) {
      if (_closing || _ended || candidate.candidate == null) return;
      if (_readyToSend) {
        _sendCandidate(candidate).catchError(_fail);
      } else {
        _localCandidates.add(candidate);
      }
    };
    _peer!.onConnectionState = (state) {
      if (_closing || _ended || !mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          _connected = true;
          _status = 'Görüşme sürüyor';
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _finish(
          'Bağlantı kurulamadı. Başka bir internet bağlantısıyla yeniden dene.',
        );
      }
    };
    if (widget.incoming) _listenCandidates();
  }

  void _audioError(Object error) {
    if (mounted && !_closing && !_ended) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userError(
              error,
              fallback: 'Ses ayarı değiştirilemedi. Yeniden dene.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_audioBusy || _microphone == null || _ended || _closing) return;
    setState(() => _audioBusy = true);
    try {
      final next = !_speakerOn;
      await Helper.setSpeakerphoneOn(next);
      if (mounted && !_ended) setState(() => _speakerOn = next);
    } catch (error) {
      _audioError(error);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _toggleReceive() async {
    if (_audioBusy || _microphone == null || _ended || _closing) return;
    final previous = _receiveMuted;
    setState(() {
      _audioBusy = true;
      _receiveMuted = !previous;
    });
    try {
      await setCallReceiveMuted(_remoteAudioTracks.values, _receiveMuted);
    } catch (error) {
      if (mounted) setState(() => _receiveMuted = previous);
      await setCallReceiveMuted(
        _remoteAudioTracks.values,
        previous,
      ).catchError((_) {});
      _audioError(error);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  void _toggleMicrophone() {
    if (_microphone == null || _ended || _closing) return;
    setState(() => _muted = !_muted);
    for (final track in _microphone!.getAudioTracks()) {
      track.enabled = !_muted;
    }
  }

  Future<void> _switchCamera() async {
    try {
      for (final track
          in _microphone?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        await Helper.switchCamera(track);
      }
    } catch (error) {
      _audioError(error);
    }
  }

  void _listenCandidates() {
    _ice = _candidates
        .where('owner', isEqualTo: widget.peer)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed ||
                !_seenCandidates.add(change.doc.id)) {
              continue;
            }
            final data = change.doc.data()!;
            final candidate = RTCIceCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String?,
              data['sdpMLineIndex'] as int?,
            );
            if (_remoteSet) {
              _peer?.addCandidate(candidate).catchError(_fail);
            } else {
              _remoteCandidates.add(candidate);
            }
          }
        }, onError: _fail);
  }

  Future<void> _sendCandidate(RTCIceCandidate candidate) => _candidates
      .add({
        'owner': _uid,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      })
      .then((_) {});
  Future<void> _flush() async {
    _readyToSend = true;
    for (final candidate in _localCandidates) {
      await _sendCandidate(candidate);
    }
    _localCandidates.clear();
  }

  Future<void> _begin() async {
    setState(() => _busy = true);
    try {
      await _prepare();
      if (_closing || _ended) return;
      final offer = await _peer!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await _peer!.setLocalDescription(offer);
      await widget.reference.set({
        'sourceKey': widget.source,
        'sourceType': widget.source.split('/')[0],
        'sourceId': widget.source.split('/')[1],
        'caller': _uid,
        'callee': widget.peer,
        'state': 'ringing',
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'createdAt': FieldValue.serverTimestamp(),
        if (widget.video) 'video': true,
      });
      if (_closing || _ended) {
        await widget.reference
            .update({'state': 'ended', 'endedAt': FieldValue.serverTimestamp()})
            .catchError((_) {});
        _cleanup().catchError((_) {});
        return;
      }
      _listenCandidates();
      await _flush();
      CallBackground.notify(widget.reference.id, 'ring').catchError((error) {
        if (mounted && !_ended) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userError(error))));
        }
      });
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy || _closing || _ended) return;
    unawaited(CallRingtone.stop(widget.reference.id).catchError((_) {}));
    unawaited(CallBackground.cancelIncoming(widget.reference.id));
    setState(() => _busy = true);
    try {
      final doc = await widget.reference.get(
        const GetOptions(source: Source.server),
      );
      final data = doc.data();
      if (data == null || data['state'] != 'ringing') {
        throw Exception('Arama sona ermiş.');
      }
      await _prepare();
      if (_closing || _ended) return;
      final offer = data['offer'] as Map;
      await _setRemote(offer);
      final answer = await _peer!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.video,
      });
      await _peer!.setLocalDescription(answer);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final current = (await transaction.get(widget.reference)).data();
        if (current?['state'] != 'ringing') {
          throw Exception('Arama sona ermiş.');
        }
        transaction.update(widget.reference, {
          'state': 'accepted',
          'answer': {'type': answer.type, 'sdp': answer.sdp},
          'startedAt': FieldValue.serverTimestamp(),
        });
      });
      if (_closing || _ended) return;
      await _flush();
      if (mounted) setState(() => _status = 'Bağlanıyor…');
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRemote(Map data) =>
      _remoteDescription ??= _applyRemote(data);
  Future<void> _applyRemote(Map data) async {
    if (_remoteSet) return;
    await _peer!.setRemoteDescription(
      RTCSessionDescription(data['sdp'] as String, data['type'] as String),
    );
    _remoteSet = true;
    for (final candidate in _remoteCandidates) {
      await _peer!.addCandidate(candidate);
    }
    _remoteCandidates.clear();
  }

  Future<void> _changed(DocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_closing || _ended) return;
    final data = doc.data();
    if (data == null) {
      if (widget.incoming || _readyToSend) {
        await _finish('Arama sona erdi.', notify: false);
      }
      return;
    }
    if (data['state'] == 'ended') {
      await _finish('Arama sona erdi.', notify: false);
      return;
    }
    final created = data['createdAt'];
    if (created is Timestamp) {
      _ringUntil = created.toDate().add(voiceCallRingDuration);
    }
    if (data['state'] == 'accepted') {
      final started = data['startedAt'];
      _started = started is Timestamp
          ? started.toDate()
          : (_started ?? DateTime.now());
      if (!_elapsed.isRunning) {
        _elapsed.start();
        if (_backgroundStarted) {
          unawaited(CallBackground.connected(widget.reference.id));
        }
        unawaited(CallBackground.cancelIncoming(widget.reference.id));
        unawaited(CallRingtone.stop(widget.reference.id).catchError((_) {}));
      }
      if (!widget.incoming && _peer != null && !_remoteSet) {
        await _setRemote(data['answer'] as Map);
      }
      if (mounted) {
        setState(
          () => _status = _connected ? 'Görüşme sürüyor' : 'Bağlanıyor…',
        );
      }
    }
  }

  void _fail(Object error) {
    _finish(
      userError(
        error,
        fallback: 'Arama kurulamadı. İnternet ve mikrofon iznini kontrol et.',
      ),
    );
  }

  Future<void> _release() async {
    _remoteAudioTracks.clear();
    if (widget.video && !_videoDisposed) {
      _videoDisposed = true;
      await _videoSetup?.catchError((_) {});
      _renderersReady = false;
      _localVideo.srcObject = null;
      _remoteVideo.srcObject = null;
      await _localVideo.dispose().catchError((_) {});
      await _remoteVideo.dispose().catchError((_) {});
    }
    final mic = _microphone;
    _microphone = null;
    for (final track in mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop().catchError((_) {});
    }
    await mic?.dispose().catchError((_) {});
    final peer = _peer;
    _peer = null;
    await peer?.close().catchError((_) {});
    await peer?.dispose().catchError((_) {});
    await CallBackground.stop(widget.reference.id);
  }

  Future<void> _finish(String status, {bool notify = true}) async {
    if (_closing || _ended) return;
    _closing = true;
    unawaited(CallRingtone.stop(widget.reference.id).catchError((_) {}));
    if (mounted && !_disposing) setState(() {});
    _ticker?.cancel();
    try {
      await _release();
      await _ice?.cancel();
      if (notify) {
        await widget.reference
            .update({'state': 'ended', 'endedAt': FieldValue.serverTimestamp()})
            .timeout(const Duration(seconds: 5))
            .catchError((_) {});
        await CallBackground.notify(
          widget.reference.id,
          'end',
        ).catchError((_) {});
      }
    } finally {
      _ended = true;
      _closing = false;
      if (mounted) setState(() => _status = status);
      _cleanup().catchError((_) {});
    }
  }

  Future<void> _cleanup() async {
    // Only the caller removes transient signaling, after the peer sees the end.
    if (widget.incoming) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    final data = (await widget.reference.get()).data();
    if (data == null || data['state'] != 'ended') return;
    final docs = await _candidates.limit(200).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(widget.reference);
    await batch.commit();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        (!_backgroundStarted &&
            (state == AppLifecycleState.paused ||
                state == AppLifecycleState.hidden))) {
      _finish('Uygulamadan çıkıldığı için arama sona erdi.');
    }
  }

  @override
  void dispose() {
    _disposing = true;
    unawaited(CallRingtone.stop(widget.reference.id).catchError((_) {}));
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _signaling?.cancel();
    _ice?.cancel();
    _native?.cancel();
    VoiceCalls.answerRequested.removeListener(_answerFromNotification);
    if (!_ended && !_closing) _finish('Arama sona erdi.');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _started == null ? null : _elapsed.elapsed;
    final time = left == null
        ? null
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final showVideo = widget.video && _renderersReady && !_closing && !_ended;
    Widget identity({bool overlay = false}) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: overlay
                ? const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  )
                : Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: overlay ? const TextStyle(color: Colors.white) : null,
          ),
          if (time != null && !_ended)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                time,
                style: TextStyle(
                  color: overlay
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
        ],
      ),
    );
    return PopScope(
      canPop: _ended,
      onPopInvokedWithResult: (popped, _) async {
        if (!popped) {
          await _finish('Arama sona erdi.');
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.video ? 'Görüntülü arama' : 'Sesli arama'),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: showVideo
                    ? LayoutBuilder(
                        builder: (context, constraints) => ClipRect(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: RTCVideoView(
                                  _remoteVideo,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                left: 12,
                                right: 12,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: identity(overlay: true),
                                ),
                              ),
                              Positioned(
                                right: 12,
                                bottom: 12,
                                width: 82,
                                height: (constraints.maxHeight * 0.35)
                                    .clamp(0, 112)
                                    .toDouble(),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: RTCVideoView(
                                    _localVideo,
                                    mirror: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                child: Icon(
                                  widget.video ? Icons.videocam : Icons.person,
                                  size: 44,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                              identity(),
                            ],
                          ),
                        ),
                      ),
              ),
              if (widget.incoming && !_ended && _started == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff247344),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _busy ? null : _accept,
                    icon: const Icon(Icons.call),
                    label: const Text('Aramayı kabul et'),
                  ),
                ),
              if (!_ended && _microphone != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: CallControls(
                    muted: _muted,
                    speakerOn: _speakerOn,
                    receiveMuted: _receiveMuted,
                    video: widget.video,
                    cameraOff: _cameraOff,
                    audioBusy: _audioBusy,
                    enabled: !_closing,
                    onMicrophone: _toggleMicrophone,
                    onSpeaker: _toggleSpeaker,
                    onReceive: _toggleReceive,
                    onCamera: () {
                      setState(() => _cameraOff = !_cameraOff);
                      for (final track in _microphone!.getVideoTracks()) {
                        track.enabled = !_cameraOff;
                      }
                    },
                    onSwitchCamera: _switchCamera,
                  ),
                ),
              if (_receiveMuted && !_ended)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Karşı tarafın sesi bu telefonda kapalı.',
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _ended ? null : const Color(0xffbf2c35),
                    foregroundColor: _ended ? null : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 18,
                    ),
                  ),
                  icon: Icon(_ended ? Icons.close : Icons.call_end),
                  onPressed: () async {
                    await _finish('Arama sona erdi.');
                    if (context.mounted) Navigator.pop(context);
                  },
                  label: Text(
                    _ended
                        ? 'Kapat'
                        : widget.incoming && _started == null
                        ? 'Reddet'
                        : 'Aramayı bitir',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
