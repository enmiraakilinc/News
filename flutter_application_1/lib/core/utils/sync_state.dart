// Yükleme zaman aşımı ve yenileme durumunu gösterir.
import 'dart:async';
import 'package:flutter/material.dart';
import 'user_errors.dart';

/// Geçici hatalarda (ağ, zaman aşımı, sunucu) hata ekranı göstermez; kısa bir
/// bekleme göstergesiyle sessizce yeniden dener. Yalnızca gerçekten devam
/// edilemeyen durumlarda mesaj ve "Tekrar dene" düğmesi çıkar.
class SyncError extends StatefulWidget {
  final String label;
  final VoidCallback onRetry;
  final Object? error;
  const SyncError({
    super.key,
    required this.label,
    required this.onRetry,
    this.error,
  });

  @override
  State<SyncError> createState() => _SyncErrorState();
}

class _SyncErrorState extends State<SyncError> {
  Timer? _timer;
  bool get _quiet => widget.error == null || isTransientError(widget.error!);

  @override
  void initState() {
    super.initState();
    if (_quiet) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) widget.onRetry();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_quiet) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              userError(
                widget.error!,
                fallback: '${widget.label} yüklenemedi. Yeniden dene.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
