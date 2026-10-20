import 'package:flutter/material.dart';
import 'user_errors.dart';

class SyncError extends StatelessWidget {
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          Text(
            error == null
                ? '$label yüklenemedi. İnternet bağlantını kontrol edip yeniden dene.'
                : userError(
                    error!,
                    fallback: '$label yüklenemedi. Yeniden dene.',
                  ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    ),
  );
}
