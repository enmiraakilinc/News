import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/security/feature_access.dart';
import '../../core/security/secure_screen.dart';
import '../../core/utils/user_errors.dart';

/// A single CameraX-backed session. Open/close operations are serialized so
/// switching lenses or backgrounding cannot leave two sessions competing.
class CameraCaptureScreen extends StatefulWidget {
  final bool video;
  const CameraCaptureScreen({super.key, required this.video});
  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Future<void> _operations = Future.value();
  bool _active = true;
  bool _busy = true;
  bool _recording = false;
  bool _flashOn = false;
  bool _screenPulse = false;
  bool _lightEnabled = false;
  bool get _front =>
      _cameras.isNotEmpty &&
      _cameras[_lens].lensDirection == CameraLensDirection.front;
  static const _light = MethodChannel('app/camera_light');
  Future<void> _screenLight(bool enabled) async {
    if (enabled == _lightEnabled) return;
    try {
      await _light.invokeMethod<void>('set', {'enabled': enabled});
      _lightEnabled = enabled;
    } catch (_) {}
  }

  bool _finished = false;
  int _lens = 0;
  String? _error;
  XFile? _savedVideo;
  bool _savedReturned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecureScreen.enable();
    _queue(_open);
  }

  void _queue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((
      Object e,
    ) async {
      await _close(preserveRecording: mounted && !_finished);
      if (mounted && !_finished) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    });
  }

  String _message(Object e) {
    if (e is Exception && e is! CameraException) return userError(e);
    if (e is CameraException) {
      if (e.code.startsWith('CameraAccess')) {
        return 'Kamera izni verilmedi. Telefon ayarlarından kamera iznini açıp tekrar dene.';
      }
      if (e.code.startsWith('AudioAccess')) {
        return 'Video için mikrofon izni gerekiyor. Telefon ayarlarından izin verip tekrar dene.';
      }
    }
    return 'Kamera kullanılamıyor. Başka bir uygulama kamerayı kullanıyorsa kapatıp tekrar dene.';
  }

  Future<void> _close({bool preserveRecording = false}) async {
    await _screenLight(false);
    _screenPulse = false;
    final controller = _controller;
    controller?.removeListener(_cameraError);
    if (preserveRecording && _recording && controller != null) {
      try {
        _savedVideo = await controller.stopVideoRecording();
      } catch (_) {
        /* The OS may already have revoked the camera. */
      }
    }
    _controller = null;
    _recording = false;
    _flashOn = false;
    if (mounted) setState(() {});
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        /* Already disconnected. */
      }
    }
  }

  Future<void> _open() async {
    if (!mounted || !_active || _finished || _savedVideo != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _close();
    await FeatureAccess.require('camera');
    if (widget.video) await FeatureAccess.require('microphone');
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
      _lens = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_lens < 0) _lens = 0;
    }
    if (_cameras.isEmpty) throw CameraException('unavailable', 'No camera');
    if (!mounted || !_active || _finished) return;
    final controller = CameraController(
      _cameras[_lens],
      widget.video ? ResolutionPreset.high : ResolutionPreset.veryHigh,
      enableAudio: widget.video,
    );
    _controller = controller;
    controller.addListener(_cameraError);
    try {
      await controller.initialize();
      // Start safely without a torch, including after a lens/lifecycle change.
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // Some lenses have no flash. Capture remains available.
      }
      if (!mounted || !_active || _finished) {
        await _close();
        return;
      }
      setState(() => _busy = false);
    } catch (_) {
      await _close();
      rethrow;
    }
  }

  void _cameraError() {
    final controller = _controller;
    if (controller?.value.hasError != true || _finished) return;
    controller!.removeListener(_cameraError);
    _queue(() async {
      throw CameraException('camera_error', controller.value.errorDescription);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      if (_recording || _savedVideo != null) return;
      _queue(_open);
    } else if (state == AppLifecycleState.inactive && _recording) {
      // Notification shade or a transient overlay is not full backgrounding.
      // Keep our existing session; do not close/reopen it just for lost focus.
      return;
    } else {
      _active = false;
      _queue(() async {
        final wasRecording = _recording;
        await _close(preserveRecording: true);
        if (mounted && !_finished) {
          setState(() {
            _busy = false;
            _error = _savedVideo == null
                ? (wasRecording
                      ? 'Kamera kesildi ve video tamamlanamadı. Yeniden deneyebilirsin.'
                      : null)
                : 'Kayıt kesildi. Çekilmiş kısmı kullanabilir veya yeniden çekebilirsin.';
          });
        }
      });
    }
  }

  void _capture() {
    if (_busy || _finished || _controller?.value.isInitialized != true) return;
    setState(() => _busy = true);
    _queue(() async {
      final controller = _controller;
      if (controller == null || !_active) return;
      if (widget.video && !_recording) {
        await controller.startVideoRecording(enablePersistentRecording: true);
        if (mounted) {
          setState(() {
            _recording = true;
            _busy = false;
          });
        }
        return;
      }
      XFile file;
      if (!widget.video && _front && _flashOn) {
        await _screenLight(true);
        if (mounted) setState(() => _screenPulse = true);
        try {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          file = await controller.takePicture();
        } finally {
          await _screenLight(false);
          if (mounted) setState(() => _screenPulse = false);
        }
      } else {
        file = widget.video
            ? await controller.stopVideoRecording()
            : await controller.takePicture();
      }
      _finished = true;
      await _close();
      if (mounted) Navigator.pop(context, file);
    });
  }

  void _toggleFlash() {
    if (_busy || _finished || _controller?.value.isInitialized != true) return;
    setState(() => _busy = true);
    _queue(() async {
      try {
        final controller = _controller;
        if (controller == null || !_active) return;
        final enabled = !_flashOn;
        if (_front) {
          if (widget.video) await _screenLight(enabled);
        } else {
          await controller.setFlashMode(
            enabled
                ? (widget.video ? FlashMode.torch : FlashMode.always)
                : FlashMode.off,
          );
        }
        if (mounted) setState(() => _flashOn = enabled);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bu kamerada flaş açılamadı. Flaşsız çekime devam edebilirsin.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  void _switchLens() {
    if (_busy || _finished || _cameras.length < 2) return;
    final next = (_lens + 1) % _cameras.length;
    setState(() => _busy = true);
    if (!_recording) {
      _lens = next;
      _queue(_open);
      return;
    }
    _queue(() async {
      try {
        final controller = _controller;
        if (controller == null || !_active) return;
        await _screenLight(false);
        try {
          await controller.setFlashMode(FlashMode.off);
        } on CameraException {
          /* Lens has no LED. */
        }
        await controller.setDescription(_cameras[next]);
        if (mounted) {
          setState(() {
            _lens = next;
            _flashOn = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _flashOn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bu cihaz kayıt sırasında kamera değiştiremedi. Kaydı bitirip diğer kamerayla devam edebilirsin.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _finished = true;
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _queue(_close);
    final saved = _savedVideo;
    if (saved != null && !_savedReturned) {
      unawaited(File(saved.path).delete().catchError((_) => File(saved.path)));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.video ? 'Video çek' : 'Fotoğraf çek')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: _front && _flashOn && widget.video
                ? Colors.white
                : Theme.of(context).colorScheme.surface,
          ),
          _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _savedVideo != null
                              ? 'Kayıt kesildi. Çekilmiş kısmı kullanabilir veya yeniden çekebilirsin.'
                              : _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _queue(() async {
                            final saved = _savedVideo;
                            _savedVideo = null;
                            if (saved != null) {
                              try {
                                await File(saved.path).delete();
                              } catch (_) {}
                            }
                            await _open();
                          }),
                          child: Text(
                            _savedVideo == null ? 'Tekrar dene' : 'Yeniden çek',
                          ),
                        ),
                        if (_savedVideo != null)
                          FilledButton(
                            onPressed: () {
                              _savedReturned = true;
                              _finished = true;
                              Navigator.pop(context, _savedVideo);
                            },
                            child: const Text('Çekilmiş kısmı kullan'),
                          ),
                      ],
                    ),
                  ),
                )
              : controller?.value.isInitialized == true
              ? Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        ValueListenableBuilder<CameraValue>(
                          valueListenable: controller!,
                          builder: (context, value, _) {
                            final orientation = value.isRecordingVideo
                                ? value.recordingOrientation
                                : value.previewPauseOrientation ??
                                      value.lockedCaptureOrientation ??
                                      value.deviceOrientation;
                            final landscape =
                                orientation ==
                                    DeviceOrientation.landscapeLeft ||
                                orientation == DeviceOrientation.landscapeRight;
                            final ratio = landscape
                                ? value.aspectRatio
                                : 1 / value.aspectRatio;
                            final scale = _front && _flashOn && widget.video
                                ? .8
                                : 1.0;
                            final width =
                                constraints.maxWidth <
                                    constraints.maxHeight * ratio
                                ? constraints.maxWidth
                                : constraints.maxHeight * ratio;
                            return SizedBox(
                              width: width * scale,
                              height: width / ratio * scale,
                              child: CameraPreview(controller),
                            );
                          },
                        ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
          if (_screenPulse)
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_controller?.value.isInitialized == true)
                IconButton(
                  tooltip: _flashOn ? 'Flaşı kapat' : 'Flaşı aç',
                  isSelected: _flashOn,
                  icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                  onPressed: _busy || _error != null ? null : _toggleFlash,
                ),
              if (_cameras.length > 1)
                IconButton(
                  tooltip: 'Kamerayı değiştir',
                  icon: const Icon(Icons.flip_camera_android),
                  onPressed: _busy ? null : _switchLens,
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: Icon(
                  _recording
                      ? Icons.stop
                      : widget.video
                      ? Icons.videocam
                      : Icons.camera_alt,
                ),
                label: Text(
                  _recording
                      ? 'Kaydı bitir'
                      : widget.video
                      ? 'Kayda başla'
                      : 'Fotoğraf çek',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
