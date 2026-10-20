import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/security/secure_screen.dart';
import '../../core/utils/user_errors.dart';

class PrivatePhotoItem {
  final Future<Uint8List> Function() load;
  final VoidCallback? onSave;
  const PrivatePhotoItem({required this.load, this.onSave});
}

Future<void> showPrivateGallery(
  BuildContext context,
  List<PrivatePhotoItem> items,
  int index,
  Uint8List initial,
) async {
  await SecureScreen.enable();
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => PrivatePhotoGallery(
        items: items,
        initialIndex: index,
        initialBytes: initial,
      ),
    ),
  );
}

class PrivatePhotoGallery extends StatefulWidget {
  final List<PrivatePhotoItem> items;
  final int initialIndex;
  final Uint8List initialBytes;
  const PrivatePhotoGallery({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.initialBytes,
  });
  @override
  State<PrivatePhotoGallery> createState() => _PrivatePhotoGalleryState();
}

class _PrivatePhotoGalleryState extends State<PrivatePhotoGallery> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  late Future<Uint8List> _photo = Future.value(widget.initialBytes);
  bool _zoomed = false;
  final _zoom = TransformationController();
  final _pointers = <int>{};
  Offset? _swipeStart;
  bool _pinching = false;
  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _swipeStart = event.position;
      _pinching = false;
    }
    _pointers.add(event.pointer);
    if (_pointers.length > 1) {
      _pinching = true;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (_pointers.length == 1 &&
        !_pinching &&
        !_zoomed &&
        _swipeStart != null) {
      final delta = event.position - _swipeStart!;
      if (delta.dx.abs() > 60 && delta.dx.abs() > delta.dy.abs()) {
        final next = _index + (delta.dx < 0 ? 1 : -1);
        if (next >= 0 && next < widget.items.length) {
          _pages.animateToPage(
            next,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      }
    }
    _pointers.remove(event.pointer);
  }

  @override
  void dispose() {
    _pages.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _change(int index) => setState(() {
    _index = index;
    _zoomed = false;
    _zoom.value = Matrix4.identity();
    // Only the visible image is downloaded, not the whole conversation.
    _photo = widget.items[index].load();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} / ${widget.items.length}'),
      actions: [
        if (widget.items[_index].onSave != null)
          IconButton(
            tooltip: 'Telefona kaydet',
            onPressed: widget.items[_index].onSave,
            icon: const Icon(Icons.save_alt),
          ),
      ],
    ),
    body: Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: (event) => _pointers.remove(event.pointer),
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: _change,
        // One-finger page gestures are handled above so they cannot win the
        // gesture arena over InteractiveViewer's two-finger zoom.
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => index != _index
            ? const SizedBox.expand()
            : FutureBuilder<Uint8List>(
                key: ValueKey(index),
                future: _photo,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              userError(
                                snapshot.error!,
                                fallback:
                                    'Fotoğraf açılamadı. Yeniden dene veya diğer fotoğrafa kaydır.',
                              ),
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              onPressed: () => _change(index),
                              child: const Text('Yeniden dene'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Center(
                    child: InteractiveViewer(
                      key: ValueKey('zoom_$index'),
                      minScale: 1,
                      maxScale: 5,
                      transformationController: _zoom,
                      panEnabled: _zoomed,
                      onInteractionUpdate: (_) {
                        final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
                        if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
                      },
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Text(
                          'Fotoğraf okunamadı. Diğer fotoğrafa kaydırabilirsin.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    ),
  );
}
