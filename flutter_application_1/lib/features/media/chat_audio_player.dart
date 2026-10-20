import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'chat_media.dart';
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
          '${folder.path}/neural_media_audio_${widget.id}_${DateTime.now().microsecondsSinceEpoch}.m4a',
        );
        await _file!.writeAsBytes(bytes);
        _fileScope = scope;
        if (!mounted) {
          await _remove();
          return;
        }
        await _player.play(DeviceFileSource(_file!.path));
      } else {
        await ChatMedia.checkAccess(widget.id);
        if (!mounted) return;
        if (_duration > Duration.zero && _position >= _duration) {
          await _player.seek(Duration.zero);
        }
        await _player.resume();
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
        ],
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
