import 'dart:async';
import 'package:flutter/material.dart';

/// Draw a first frame before invoking plugins; never leave a blank window.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.child,
    this.timeout = const Duration(seconds: 8),
  });
  final Future<void> Function() initialize;
  final Widget child;
  final Duration timeout;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      await widget.initialize().timeout(widget.timeout);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xff171923),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_failed)
              const CircularProgressIndicator(color: Colors.white70),
            const SizedBox(height: 20),
            Text(
              _failed ? 'Başlatma tamamlanamadı.' : 'Yükleniyor…',
              style: const TextStyle(color: Colors.white),
            ),
            if (_failed) ...[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _start,
                child: const Text('Tekrar dene'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () => setState(() => _ready = true),
                child: const Text('Bildirimler olmadan devam et'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
