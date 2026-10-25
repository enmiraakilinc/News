import 'playback_speed_menu.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'chat_media.dart';
import 'audio_file_types.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/utils/user_errors.dart';

class ChatAudioPlayer extends StatefulWidget {
  final String id;
  final String name;
  const ChatAudioPlayer({super.key, required this.id, required this.name});
  @override
  State<ChatAudioPlayer> createState() => _ChatAudioPlayerState();
}

class _ChatAudioPlayerState extends State<ChatAudioPlayer> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  File? _file;
  String? _fileScope;
  bool _busy = false;
  double _progress = 0;
  bool _playing = false;
  double _speed = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.onPositionChanged.listen((v) {
        if (mounted) setState(() => _position = v);
      }),
    );
    _subs.add(
      _player.onDurationChanged.listen((v) {
        if (mounted) setState(() => _duration = v);
      }),
    );
    _subs.add(
      _player.onPlayerStateChanged.listen((v) {
        if (mounted) setState(() => _playing = v == PlayerState.playing);
      }),
    );
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      // Recheck server lifetime and permissions even when a local copy exists.
      final scope = await ChatMedia.accessScope();
      if (_file != null && _fileScope != scope) {
        await _player.stop();
        await _remove();
        _file = null;
      }
      if (_file == null) {
        _progress = 0;
        final bytes = await ChatMedia.download(
          widget.id,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
        );
        if (!mounted) return;
        final folder = await getTemporaryDirectory();
        _file = File(
          '${folder.path}/neural_media_audio_${widget.id}_${DateTime.now().microsecondsSinceEpoch}.${AudioFileTypes.extension(widget.name)}',
        );
        await _file!.writeAsBytes(bytes);
        _fileScope = scope;
        if (!mounted) {
          await _remove();
          return;
        }
        await _player.play(DeviceFileSource(_file!.path));
        await _player.setPlaybackRate(_speed);
      } else {
        await ChatMedia.checkAccess(widget.id);
        if (!mounted) return;
        if (_duration > Duration.zero && _position >= _duration) {
          await _player.seek(Duration.zero);
        }
        if (_duration == Duration.zero) {
          await _player.play(DeviceFileSource(_file!.path));
          await _player.setPlaybackRate(_speed);
        } else {
          await _player.resume();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback: 'Sesli mesaj açılamadı. Yeniden dene.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setSpeed(double value) async {
    final previous = _speed;
    setState(() => _speed = value);
    try {
      if (_file != null) await _player.setPlaybackRate(value);
    } catch (_) {
      if (mounted) {
        setState(() => _speed = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oynatma hızı değiştirilemedi.')),
        );
      }
    }
  }

  Future<void> _openExternal() async {
    if (_busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başka uygulamada aç'),
        content: const Text(
          'Ses dosyası seçtiğin uygulamaya aktarılır. O uygulama dosyayı saklayabilir. Telefonun ses kaydedicisi bu dosya türünü destekliyorsa onunla da açabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aç'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _player.pause();
      final scope = await ChatMedia.accessScope();
      await ChatMedia.checkAccess(widget.id);
      if (_file != null && (_fileScope != scope || !await _file!.exists())) {
        await _remove();
        _file = null;
      }
      if (_file == null) {
        final bytes = await ChatMedia.download(
          widget.id,
          onProgress: (v) {
            if (mounted) setState(() => _progress = v);
          },
        );
        if (await ChatMedia.accessScope() != scope) {
          throw Exception('Sohbet bağlantısı değişti. Yeniden dene.');
        }
        final folder = await getTemporaryDirectory();
        _file = File(
          '${folder.path}/neural_media_audio_${widget.id}_${DateTime.now().microsecondsSinceEpoch}.${AudioFileTypes.extension(widget.name)}',
        );
        await _file!.writeAsBytes(bytes);
        _fileScope = scope;
      }
      if (!mounted) {
        await _remove();
        return;
      }
      final result = await OpenFilex.open(
        _file!.path,
        type: AudioFileTypes.mime(widget.name),
      );
      if (result.type != ResultType.done) {
        throw Exception(
          'Bu ses türünü açabilen bir uygulama bulunamadı. Sesi buradaki oynat düğmesinden dinleyebilirsin.',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback:
                    'Ses başka uygulamada açılamadı. Buradaki oynat düğmesini kullanabilirsin.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    try {
      await _file?.delete();
    } catch (_) {}
  }

  Future<void> _close() async {
    await _player.dispose();
    await _remove();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    unawaited(_close());
    super.dispose();
  }

  String _time(Duration v) =>
      '${v.inMinutes}:${(v.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          IconButton(
            tooltip: _playing ? 'Duraklat' : 'Sesli mesajı dinle',
            onPressed: _busy ? null : _toggle,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  )
                : Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Text(
              _busy && _file == null
                  ? '${widget.name}\nYükleniyor · %${(_progress * 100).round()}'
                  : widget.name,
            ),
          ),
          PlaybackSpeedMenu(
            value: _speed,
            onChanged: _setSpeed,
            enabled: !_busy,
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _openExternal,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Başka uygulamada aç'),
        ),
      ),
      if (_file != null) ...[
        Slider(
          value: _position.inMilliseconds.toDouble().clamp(
            0,
            _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
          ),
          max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
          onChanged: _duration == Duration.zero || _busy
              ? null
              : (v) {
                  _player.seek(Duration(milliseconds: v.round()));
                },
        ),
        Text('${_time(_position)} / ${_time(_duration)}'),
      ],
    ],
  );
}
