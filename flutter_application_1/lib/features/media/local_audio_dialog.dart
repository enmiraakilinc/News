import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'audio_file_types.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class LocalAudioDialog extends StatefulWidget {
  final File file;
  final String title;
  final bool allowExternal;
  const LocalAudioDialog({
    super.key,
    required this.file,
    required this.title,
    this.allowExternal = false,
  });
  @override
  State<LocalAudioDialog> createState() => LocalAudioDialogState();
}

class LocalAudioDialogState extends State<LocalAudioDialog>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  Duration _position = Duration.zero, _duration = Duration.zero;
  bool _playing = false, _started = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.onPositionChanged.listen((v) {
      if (mounted) setState(() => _position = v);
    });
    _player.onDurationChanged.listen((v) {
      if (mounted) setState(() => _duration = v);
    });
    _player.onPlayerStateChanged.listen((v) {
      if (mounted) setState(() => _playing = v == PlayerState.playing);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  Future<void> _openWith() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Birlikte aç'),
        content: const Text(
          'Seçeceğin uygulama bu ses dosyasına erişebilir ve kendi kopyasını saklayabilir. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Devam et'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      await _player.pause();
      if (Platform.isAndroid) {
        await const MethodChannel(
          'app/audio_files',
        ).invokeMethod<void>('openWith', {'path': widget.file.path});
      } else {
        final result = await OpenFilex.open(
          widget.file.path,
          type: AudioFileTypes.mime(widget.file.path),
        );
        if (result.type != ResultType.done) throw const FormatException();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PlatformException && e.code == 'no_app'
                ? 'Bu ses biçimini açabilen bir uygulama bulunamadı.'
                : 'Ses dosyası açılamadı. Uyumlu bir ses uygulamasıyla yeniden dene.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: _playing ? 'Duraklat' : 'Oynat',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: () async {
            try {
              if (_playing) {
                await _player.pause();
              } else if (_started) {
                await _player.resume();
              } else {
                await _player.play(DeviceFileSource(widget.file.path));
                _started = true;
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sesli not oynatılamadı.')),
                );
              }
            }
          },
        ),
        Slider(
          value: _position.inMilliseconds
              .clamp(0, _duration.inMilliseconds)
              .toDouble(),
          max: _duration.inMilliseconds > 0
              ? _duration.inMilliseconds.toDouble()
              : 1,
          onChanged: _duration > Duration.zero
              ? (v) => _player.seek(Duration(milliseconds: v.round()))
              : null,
        ),
      ],
    ),
    actions: [
      if (widget.allowExternal)
        TextButton.icon(
          onPressed: _openWith,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Birlikte aç'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
