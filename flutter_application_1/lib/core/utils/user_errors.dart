import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

String userError(
  Object error, {
  String fallback = 'İşlem tamamlanamadı. Yeniden dene.',
}) {
  if (error is TimeoutException || error is SocketException) {
    return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
  }
  if (error is FileSystemException) {
    return 'Dosya okunamadı veya kaydedilemedi. Dosyanın hâlâ bulunduğunu ve telefonda boş alan olduğunu kontrol et.';
  }
  if (error is FormatException) {
    return 'Bu içerik okunamadı. Dosyayı veya girdiğin bilgiyi kontrol edip yeniden dene.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Sunucu/sinyalleşme izni reddedildi (oturum veya kural yetkisi eksik).';
      case 'unavailable':
      case 'network-request-failed':
        return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
      case 'resource-exhausted':
        return 'Hizmetin kullanım sınırına ulaşıldı. Daha sonra yeniden dene.';
      case 'not-found':
        return 'İçerik artık bulunamıyor. Silinmiş veya süresi dolmuş olabilir.';
      case 'unauthenticated':
        return 'Hesap oturumun doğrulanamadı. Hesabına yeniden giriş yapıp dene.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Hesap bilgileri doğrulanamadı. Hesap kodunu ve şifreni kontrol et.';
      case 'too-many-requests':
        return 'Kısa sürede çok fazla deneme yapıldı. Biraz bekleyip yeniden dene.';
      case 'deadline-exceeded':
        return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
      case 'storage-full':
        return 'Depolama alanı dolu. Gereksiz dosyaları kaldırıp yeniden dene.';
    }
    return 'Sunucu bu işlemi tamamlayamadı. Biraz sonra yeniden dene.';
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final detail =
        '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    if (code.contains('in_use') ||
        code.contains('inuse') ||
        code.contains('notreadable') ||
        code.contains('not_readable') ||
        code.contains('busy') ||
        detail.contains('in_use') ||
        detail.contains('inuse') ||
        detail.contains('notreadable') ||
        detail.contains('not_readable') ||
        detail.contains('busy')) {
      return 'Mikrofon/kamera başka bir uygulama tarafından kullanılıyor.';
    }
    if (detail.contains('camera') &&
        (code.contains('permission') ||
            code.contains('denied') ||
            detail.contains('permission') ||
            detail.contains('denied'))) {
      return 'Kamera izni kapalı, ayarlardan izin verin.';
    }
    if (code.contains('permission') ||
        code.contains('access_denied') ||
        code.contains('accessdenied') ||
        code.contains('securityexception') ||
        code.contains('not_authorized') ||
        code.contains('notauthorized') ||
        detail.contains('microphone') ||
        detail.contains('record_audio')) {
      return 'Mikrofon izni kapalı, ayarlardan izin verin.';
    }
    if (code.contains('not_found') || code.contains('no_app')) {
      return 'Dosya bulunamadı veya açılamadı. Dosyanın hâlâ telefonda olduğunu kontrol et.';
    }
    return 'Bu işlem için gerekli izin kapalı. Telefon ayarlarından açıp yeniden dene.';
  }
  final message = error.toString().replaceFirst('Exception: ', '');
  final lower = message.toLowerCase();
  if (lower.contains('erişim iznin') ||
      lower.contains('permission-denied') ||
      lower.contains('permission_denied')) {
    return 'Sunucu/sinyalleşme izni reddedildi (oturum veya kural yetkisi eksik).';
  }
  if (lower.contains('timeout') ||
      lower.contains('deadline') ||
      lower.contains('zaman aş')) {
    return 'Arama zaman aşımına uğradı. Bağlantı yetişmedi.';
  }
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('failed host')) {
    return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
  }
  if (lower.contains('in_use') ||
      lower.contains('notreadable') ||
      lower.contains('busy')) {
    return 'Mikrofon/kamera başka bir uygulama tarafından kullanılıyor.';
  }
  if (lower.contains('camera') &&
      (lower.contains('permission') || lower.contains('denied'))) {
    return 'Kamera izni kapalı, ayarlardan izin verin.';
  }
  if (lower.contains('microphone') || lower.contains('record_audio')) {
    return 'Mikrofon izni kapalı, ayarlardan izin verin.';
  }
  if (lower.contains('rejected')) return 'Karşı taraf aramayı reddetti.';
  if (RegExp(
    r'exception|firebase|stacktrace|errno|https?://',
    caseSensitive: false,
  ).hasMatch(message)) {
    return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
  }
  if (message.isNotEmpty && message.length < 180) return message;
  return fallback;
}
