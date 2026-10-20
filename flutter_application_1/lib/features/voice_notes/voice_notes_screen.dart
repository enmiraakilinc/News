import '../../core/utils/sync_state.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/security/feature_access.dart';
import '../../core/security/microphone_session.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';
import '../../core/notifications/notif_prefs.dart';
import '../../core/utils/user_errors.dart';

const List<String> _aylar = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
String _tarih(DateTime d) =>
    '${d.day} ${_aylar[d.month - 1]} ${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Sesli notlar. Eşleşme varsa notlar UÇTAN UCA şifrelenip Firestore üzerinden
/// iki telefonda da senkronlanır (istenirse silinebilir). Eşleşme yoksa eski
/// yerel-sadece davranış korunur; eski yerel kayıtlar kaybolmaz.
class VoiceNotesScreen extends StatefulWidget {
  final Future<void> Function(String path, String title)? sendMessage;
  final String? screenTitle, confirmLabel;
  const VoiceNotesScreen({
    super.key,
    this.sendMessage,
    this.screenTitle,
    this.confirmLabel,
  });

  @override
  State<VoiceNotesScreen> createState() => _VoiceNotesScreenState();
}

class _VoiceNotesScreenState extends State<VoiceNotesScreen> {
  static const String _key = 'voice_notes_v1';

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _loading = true;
  String? _coupleId;
  String? _secret;
  bool get _paired => _coupleId != null && _secret != null;
  Stream<List<VoiceNote>>? _sharedStream;

  void _retryShared() {
    CoupleService.resetConnection();
    setState(() {
      _sharedStream = CoupleService.voiceNotesStream(_coupleId!, _secret!);
    });
  }

  // Eski, bu telefonda kalmış (paylaşılmamış) kayıtlar.
  List<Map<String, dynamic>> _localNotes = [];

  bool _recording = false;
  bool _recordingPaused = false;
  String? _draftPath;
  String? _recordingPath;
  bool _busy = false; // yükleme sırasında
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  /// Çalan notun benzersiz anahtarı: paylaşımlı için 'sh_' + id, yerel için 'lo_' + path.
  String? _playingKey;
  StreamSubscription? _completeSub;
  final List<StreamSubscription> _playbackSubs = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playPaused = true;

  /// Paylaşımlı notların çözülmüş sesini oynatmak için geçici dosya önbelleği.
  final Map<String, String> _cache = {};

  @override
  void initState() {
    super.initState();
    _init();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playPaused = true;
          _position = _duration;
        });
      }
    });
    _playbackSubs.add(
      _player.onPositionChanged.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
    );
    _playbackSubs.add(
      _player.onDurationChanged.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
    );
    _playbackSubs.add(
      _player.onPlayerStateChanged.listen((value) {
        if (mounted) setState(() => _playPaused = value != PlayerState.playing);
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completeSub?.cancel();
    for (final subscription in _playbackSubs) {
      subscription.cancel();
    }
    final unsaved = _draftPath ?? _recordingPath;
    unawaited(_disposeAudio(unsaved));
    super.dispose();
  }

  Future<void> _disposeAudio(String? unsaved) async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    await MicrophoneSession.stop('voice').catchError((_) {});
    try {
      await _player.dispose();
    } catch (_) {}
    if (unsaved != null) await _deleteFile(unsaved);
  }

  Future<void> _init() async {
    if (widget.sendMessage != null) {
      setState(() => _loading = false);
      return;
    }
    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    await _loadLocal();
    if (!mounted) return;
    setState(() {
      _coupleId = cid;
      _secret = sec;
      _sharedStream = cid != null && sec != null
          ? CoupleService.voiceNotesStream(cid, sec)
          : null;
      _loading = false;
    });
  }

  // ── Yerel (eski) kayıtlar ────────────────────────────────
  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      list = (jsonDecode(raw) as List)
          .map(
            (e) => <String, dynamic>{
              'path': (e['path'] ?? '').toString(),
              'title': (e['title'] ?? '').toString(),
              'date': (e['date'] ?? '').toString(),
            },
          )
          .toList();
    }
    _localNotes = list;
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_localNotes));
  }

  String _msg(Object e) => userError(e);

  // ── Kayıt ────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_busy || _recording || _draftPath != null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _stop();
      await FeatureAccess.require('microphone');
      if (!await _recorder.hasPermission()) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Mikrofon izni gerekli.")),
        );
        return;
      }
      if (!mounted ||
          !await MicrophoneSession.ensureDrawerHidden(
            context,
            allowLegacy: true,
          )) {
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      final path =
          '${dir.path}/ses_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // Ses için düşük bit hızı: kalite fark etmez ama dosya küçük kalır →
      // paylaşımlı notlar ücretsiz Firestore sınırına (~1MB) sığar.
      await MicrophoneSession.start(
        'voice',
        onVoiceStop: () async {
          while (_busy && mounted) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          if (mounted && _recording) await _stopRecording();
        },
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      _recordingPath = path;
      if (!mounted) {
        await _recorder.cancel();
        await MicrophoneSession.stop('voice');
        return;
      }
      setState(() {
        _recording = true;
        _recordingPaused = false;
        _elapsed = Duration.zero;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && !_recordingPaused) {
          setState(() => _elapsed += const Duration(seconds: 1));
        }
      });
    } catch (error) {
      await MicrophoneSession.stop('voice').catchError((_) {});
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(_msg(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      _timer?.cancel();
      final path = await _recorder.stop();
      _recordingPath = null;
      if (!mounted) {
        if (path != null) await _deleteFile(path);
        return;
      }
      setState(() {
        _recording = false;
        _recordingPaused = false;
        _draftPath = path;
      });
      if (path == null) return;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(error))));
      }
    } finally {
      await MicrophoneSession.stop('voice').catchError((_) {});
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() async {
    final path = _draftPath;
    if (_busy || path == null) return;
    setState(() => _busy = true);
    try {
      await _stop();
      if (!mounted) return;
      final title = await _askTitle(context);
      if (title == null || !mounted) return;
      final baslik = title.isEmpty
          ? (widget.sendMessage == null ? 'Sesli not' : 'Sesli mesaj')
          : title;
      var saved = false;
      if (widget.sendMessage != null) {
        await widget.sendMessage!(path, baslik);
        saved = true;
        await _deleteFile(path);
      } else if (_paired) {
        saved = await _uploadShared(path, baslik);
      } else {
        await _keepLocal(path, baslik);
        saved = true;
      }
      if (saved) {
        _draftPath = null;
        if (mounted) setState(() {});
        if (mounted && widget.sendMessage != null) Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _uploadShared(String path, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      await CoupleService.addVoiceNote(audioBytes: bytes, title: title);
      // Yüklendi → geçici kayıt dosyasını sil (artık Firestore'da).
      try {
        await File(path).delete();
      } catch (_) {}
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Sesli not eklendi — ikinizde de görünecek 💜"),
        ),
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_msg(e))));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _pauseRecording() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      if (_recordingPaused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
      if (mounted) setState(() => _recordingPaused = !_recordingPaused);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_msg(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardDraft({bool restart = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _stop();
      if (_recording) await _recorder.cancel();
      await MicrophoneSession.stop('voice');
      _timer?.cancel();
      final path = _draftPath ?? _recordingPath;
      if (path != null) await _deleteFile(path);
      if (!mounted) return;
      setState(() {
        _draftPath = null;
        _recordingPath = null;
        _recording = false;
        _recordingPaused = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (restart && mounted) await _startRecording();
  }

  Future<void> _keepLocal(String path, String title) async {
    final now = DateTime.now();
    setState(() {
      _localNotes.insert(0, {
        'path': path,
        'title': title,
        'date': '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}',
      });
    });
    await _saveLocal();
  }

  Future<String?> _askTitle(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sesli Not Başlığı"),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: "örn: Sana bir şarkı"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }

  // ── Oynatma ──────────────────────────────────────────────
  Future<void> _stop() async {
    await _player.stop();
    if (mounted) {
      setState(() {
        _playingKey = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _playPaused = true;
      });
    }
  }

  Future<void> _playFile(String key, String filePath) async {
    if (_playingKey == key) {
      await _togglePlayback();
      return;
    }
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _playingKey = key;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.play(DeviceFileSource(filePath));
    if (mounted) setState(() => _playingKey = key);
  }

  Future<void> _playShared(VoiceNote n) async {
    if (n.audio == null) return;
    final key = 'sh_${n.id}';
    if (_playingKey == key) {
      await _togglePlayback();
      return;
    }
    // Bana gelen ve henüz dinlemediğim notu "dinlendi" işaretle → gönderen görür.
    if (!n.fromMe && !n.readByRecipient) {
      CoupleService.markVoiceNoteRead(n.id);
    }
    // Sesi geçici dosyaya yazıp oradan çal (önbellekli).
    String? filePath = _cache[n.id];
    if (filePath == null || !await File(filePath).exists()) {
      final tmp = await getTemporaryDirectory();
      filePath = '${tmp.path}/vn_${n.id}.m4a';
      await File(filePath).writeAsBytes(n.audio!);
      _cache[n.id] = filePath;
    }
    await _playFile(key, filePath);
  }

  Future<void> _togglePlayback() async {
    if (_playPaused) {
      if (_duration > Duration.zero && _position >= _duration) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    } else {
      await _player.pause();
    }
  }

  Widget _timeline() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Slider(
        value: _position.inMilliseconds.toDouble().clamp(
          0,
          _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
        ),
        max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
        onChanged: _duration == Duration.zero
            ? null
            : (value) {
                final position = Duration(milliseconds: value.round());
                setState(() => _position = position);
                unawaited(_player.seek(position));
              },
      ),
      Text(
        '${_fmt(_position)} / ${_fmt(_duration)}',
        style: const TextStyle(fontSize: 11),
      ),
    ],
  );

  // ── Silme ────────────────────────────────────────────────
  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sesli notu sil"),
        content: const Text("Bu kayıt kalıcı olarak silinecek. Emin misin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteShared(VoiceNote n) async {
    if (!await _confirmDelete()) return;
    if (_playingKey == 'sh_${n.id}') await _stop();
    await CoupleService.deleteVoiceNote(n.id);
  }

  Future<void> _deleteLocal(int i) async {
    if (!await _confirmDelete()) return;
    final path = _localNotes[i]['path'] as String;
    if (_playingKey == 'lo_$path') await _stop();
    setState(() => _localNotes.removeAt(i));
    await _saveLocal();
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  // ── Yapı ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.screenTitle ??
              (widget.sendMessage == null ? 'Sesli Notlar' : 'Sesli mesaj'),
        ),
        actions: [
          if (widget.sendMessage == null)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: "Bildirim yazısı",
              onPressed: () => editNotifText(context, kNotifVoice),
            ),
        ],
      ),
      floatingActionButton: _draftPath != null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _recording ? Colors.red : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(
                _busy
                    ? "Yükleniyor…"
                    : _recording
                    ? "Bitir  ${_fmt(_elapsed)}"
                    : "Kaydet",
              ),
              onPressed: _busy
                  ? null
                  : (_recording ? _stopRecording : _startRecording),
            ),
      bottomNavigationBar: !_recording && _draftPath == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_recording) ...[
                      Text(
                        _recordingPaused
                            ? 'Kayıt duraklatıldı'
                            : 'Kayıt sürüyor',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _busy ? null : _pauseRecording,
                            icon: Icon(
                              _recordingPaused ? Icons.mic : Icons.pause,
                            ),
                            label: Text(
                              _recordingPaused
                                  ? 'Kayda devam et'
                                  : 'Kaydı duraklat',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _discardDraft(restart: true),
                            child: const Text('Yeniden çek'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        widget.confirmLabel == null
                            ? 'Göndermeden önce kaydını dinleyebilirsin.'
                            : 'Kaydetmeden önce kaydını dinleyebilirsin.',
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _playFile('draft', _draftPath!),
                        icon: Icon(
                          _playingKey == 'draft' && !_playPaused
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          _playingKey == 'draft' && !_playPaused
                              ? 'Dinlemeyi duraklat'
                              : 'Ön dinleme',
                        ),
                      ),
                      if (_playingKey == 'draft') _timeline(),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => _discardDraft(),
                            child: const Text('Vazgeç'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _discardDraft(restart: true),
                            child: const Text('Yeniden çek'),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _saveDraft,
                            child: Text(
                              _busy
                                  ? 'Bekleniyor…'
                                  : _paired || widget.sendMessage != null
                                  ? (widget.confirmLabel ?? 'Onayla ve gönder')
                                  : 'Onayla ve kaydet',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : widget.sendMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.confirmLabel == null
                      ? 'Kaydet düğmesine bas. Kaydı bitirdikten sonra dinleyip onaylayarak gönderebilirsin.'
                      : 'Kaydet düğmesine bas. Kaydı bitirdikten sonra dinleyip onaylayarak notlarına ekleyebilirsin.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _paired
          ? _buildPaired()
          : _buildUnpaired(),
    );
  }

  Widget _buildUnpaired() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.link_off,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Sesli notların ikinizde de görünmesi için 'Geleceğe Mektup'tan "
                  "eşleşin. Şimdilik kayıtların bu telefonda kalır.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_localNotes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text(
              "Henüz sesli not yok.\nMikrofona basıp ilk kaydını bırak.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          for (int i = 0; i < _localNotes.length; i++) _localTile(i),
      ],
    );
  }

  Widget _buildPaired() {
    return StreamBuilder<List<VoiceNote>>(
      stream: _sharedStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return SyncError(label: 'Kayıtlar', onRetry: _retryShared);
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shared = snap.data ?? [];
        if (shared.isEmpty && _localNotes.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "Henüz sesli not yok.\nMikrofona basıp ilk kaydınızı bırakın.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
          children: [
            for (final n in shared) _sharedTile(n),
            if (_localNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.phone_iphone, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(
                    "Bu telefonda (paylaşılmadı)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (int i = 0; i < _localNotes.length; i++) _localTile(i),
            ],
          ],
        );
      },
    );
  }

  Widget _sharedTile(VoiceNote n) {
    final playing = _playingKey == 'sh_${n.id}';
    final cozulemedi = n.audio == null;
    final okundu = n.readByRecipient;
    // Bana gelmiş ama henüz dinlemediğim not = dikkat çekmeli.
    final yeniGelen = !n.fromMe && !okundu && !cozulemedi;
    // Dinlediğim notlar soluklaşır (mektuplardaki gibi).
    final soluk = !n.fromMe && okundu;

    // Durum satırı
    late String durum;
    late Color durumColor;
    FontWeight durumWeight = FontWeight.normal;
    if (cozulemedi) {
      durum = "Çözülemedi (gizli kelime farklı olabilir)";
      durumColor = Colors.grey;
    } else if (n.fromMe) {
      durum = okundu ? "Dinlendi ✓✓" : "İletildi · henüz dinlenmedi";
      durumColor = okundu ? Colors.green.shade600 : Colors.grey;
      durumWeight = okundu ? FontWeight.w600 : FontWeight.normal;
    } else if (yeniGelen) {
      durum = "● Yeni · dokun ve dinle";
      durumColor = Theme.of(context).colorScheme.onSurface;
      durumWeight = FontWeight.bold;
    } else {
      durum = "Dinlendi";
      durumColor = Colors.grey;
    }

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: yeniGelen
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: yeniGelen ? 1.5 : 0,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          child: IconButton(
            icon: Icon(
              playing && !_playPaused ? Icons.pause : Icons.play_arrow,
              color: cozulemedi
                  ? Colors.grey
                  : Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: cozulemedi || _busy || _recording
                ? null
                : () => _playShared(n),
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(n.title)),
            if (yeniGelen)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "YENİ",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${n.fromMe ? 'Sen' : 'Eşin'}${n.createdAt != null ? ' · ${_tarih(n.createdAt!)}' : ''}",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              durum,
              style: TextStyle(
                fontSize: 12,
                color: durumColor,
                fontWeight: durumWeight,
              ),
            ),
            if (playing) _timeline(),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteShared(n),
        ),
      ),
    );
    return soluk ? Opacity(opacity: 0.55, child: card) : card;
  }

  Widget _localTile(int i) {
    final note = _localNotes[i];
    final path = note['path'] as String;
    final playing = _playingKey == 'lo_$path';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.outlineVariant,
          child: IconButton(
            icon: Icon(
              playing && !_playPaused ? Icons.pause : Icons.play_arrow,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: _busy || _recording
                ? null
                : () => _playFile('lo_$path', path),
          ),
        ),
        title: Text(note['title'] as String),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _dateLabel(note['date'] as String),
              style: const TextStyle(fontSize: 12),
            ),
            if (playing) _timeline(),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteLocal(i),
        ),
      ),
    );
  }

  String _dateLabel(String raw) {
    try {
      final parts = raw.split(' ');
      final d = parts[0].split('-').map(int.parse).toList();
      final t = parts[1].split(':').map(int.parse).toList();
      return _tarih(DateTime(d[0], d[1], d[2], t[0], t[1]));
    } catch (_) {
      return raw;
    }
  }
}
