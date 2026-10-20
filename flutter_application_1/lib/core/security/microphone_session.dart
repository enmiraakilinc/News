import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android foreground session; recording itself stays with its existing owner.
class MicrophoneSession {
  static const channel = MethodChannel('app/microphone_session');
  static Future<void> Function()? _voiceStop;
  static bool _initialized = false;
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static void _init() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') await _voiceStop?.call();
    });
  }

  static Future<void> start(
    String mode, {
    Future<void> Function()? onVoiceStop,
  }) async {
    if (!supported) return;
    _init();
    if (mode == 'voice') _voiceStop = onVoiceStop;
    try {
      await channel.invokeMethod<void>('start', {'mode': mode});
    } catch (_) {
      if (mode == 'voice') _voiceStop = null;
      rethrow;
    }
  }

  static Future<bool> ensureDrawerHidden(
    BuildContext context, {
    bool allowLegacy = false,
  }) async {
    if (!supported) return true;
    final settings =
        await channel.invokeMapMethod<String, dynamic>('prepare') ?? {};
    if (settings['drawerHidden'] == true ||
        (allowLegacy && settings['supported'] == false)) {
      return true;
    }
    if (!context.mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mikrofon bildirim görünümü'),
        content: Text(
          settings['supported'] == false
              ? 'Bildirim çekmecesi olmadan arka plan mikrofonu için Android 13 veya yenisi gerekiyor.'
              : 'Açılan Android ayarında yalnızca “Mikrofon oturumları” bildirim kanalını kapat. Diğer bildirimlerini kapatman gerekmez. Sonra uygulamaya dönüp yeniden başlat. Yeşil mikrofon göstergesi ve sistemin çalışan uygulamalar kaydı görünür kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          if (settings['supported'] != false)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kanal ayarını aç'),
            ),
        ],
      ),
    );
    if (open == true) await channel.invokeMethod<void>('settings');
    return false;
  }

  static Future<void> requestStop() async {
    if (supported) await channel.invokeMethod<void>('requestStop');
  }

  static Future<void> stop(String mode) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('stop', {'mode': mode});
    } finally {
      if (mode == 'voice') _voiceStop = null;
    }
  }

  static Future<Map<String, dynamic>> status() async {
    if (!supported) return {};
    return await channel.invokeMapMethod<String, dynamic>('status') ?? {};
  }
}
