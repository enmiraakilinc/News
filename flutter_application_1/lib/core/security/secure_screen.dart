import 'package:flutter/services.dart';

/// Android'de bütün uygulama ekranlarını FLAG_SECURE ile korur.
/// Native pencere açılıştan itibaren korumalıdır; disable da korumayı korur.
class SecureScreen {
  static const MethodChannel _ch = MethodChannel('app/secure_screen');

  static Future<void> enable() async {
    try {
      await _ch.invokeMethod('enable');
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await _ch.invokeMethod('disable');
    } catch (_) {}
  }
}
