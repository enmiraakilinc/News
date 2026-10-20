import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class LocalAudioDialog extends StatefulWidget {
  final File file;
  final String title;
  const LocalAudioDialog({super.key, required this.file, required this.title});
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
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
