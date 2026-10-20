import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/security/secure_screen.dart';

Future<void> showPrivatePhoto(
  BuildContext context,
  Uint8List bytes, {
  VoidCallback? onSave,
}) async {
  await SecureScreen.enable();
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            if (onSave != null)
              IconButton(
                tooltip: 'Telefona kaydet',
                onPressed: onSave,
                icon: const Icon(Icons.save_alt),
              ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Fotoğraf okunamadı. Dosya eksik veya bozulmuş olabilir; yeniden göndermeyi dene.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PrivateVideoScreen extends StatefulWidget {
  final File file;
  final VoidCallback? onSave;
  const PrivateVideoScreen({super.key, required this.file, this.onSave});
  @override
  State<PrivateVideoScreen> createState() => _PrivateVideoScreenState();
}

class _PrivateVideoScreenState extends State<PrivateVideoScreen>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  final _zoom = TransformationController();
  bool _ready = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecureScreen.enable();
    _controller = VideoPlayerController.file(widget.file);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.addListener(_changed);
      await _controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      actions: [
        if (_ready)
          IconButton(
            tooltip: 'Yakınlaştırmayı sıfırla',
            onPressed: () => _zoom.value = Matrix4.identity(),
            icon: const Icon(Icons.zoom_out_map),
          ),
        if (widget.onSave != null)
          IconButton(
            tooltip: 'Telefona kaydet',
            onPressed: widget.onSave,
            icon: const Icon(Icons.save_alt),
          ),
      ],
    ),
    body: Center(
      child: _failed || _controller.value.hasError
          ? const Text(
              'Video açılamadı.',
              style: TextStyle(color: Colors.white),
            )
          : !_ready
          ? const CircularProgressIndicator()
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    minScale: 1,
                    maxScale: 5,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),
                ),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.all(16),
                ),
                IconButton(
                  color: Colors.white,
                  tooltip: _controller.value.isPlaying ? 'Duraklat' : 'Oynat',
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: () => _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play(),
                ),
              ],
            ),
    ),
  );
}
