import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

String userError(
  Object error, {
  String fallback = 'İşlem tamamlanamadı. Yeniden dene.',
}) {
  if (error is TimeoutException || error is SocketException) {
    return 'Bağlantı kurulamadı. İnternetini kontrol edip yeniden dene.';
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
        return 'Bu içeriğe şu anda erişilemiyor. Sohbet bağlantını kontrol et; ekin süresi de dolmuş olabilir.';
      case 'unavailable':
      case 'network-request-failed':
        return 'Bağlantı kurulamadı. İnternetini kontrol edip yeniden dene.';
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
        return 'Sunucu zamanında yanıt vermedi. İnternetini kontrol edip yeniden dene.';
      case 'storage-full':
        return 'Depolama alanı dolu. Gereksiz dosyaları kaldırıp yeniden dene.';
    }
    return fallback;
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.contains('permission') ||
        code.contains('access_denied') ||
        code.contains('accessdenied')) {
      return 'Bu işlem için gerekli izin kapalı. Telefon ayarlarından uygulamanın ilgili iznini açıp yeniden dene.';
    }
    if (code.contains('not_found') || code.contains('no_app')) {
      return 'Dosya bulunamadı veya açılamadı. Dosyanın hâlâ telefonda olduğunu kontrol et.';
    }
    return fallback;
  }
  final message = error.toString().replaceFirst('Exception: ', '');
  if (error is Exception &&
      !message.startsWith('[') &&
      message.length < 180 &&
      !RegExp(
        r'error|exception|denied|invalid|failed|stacktrace|errno|https?://|[a-z]:\\',
        caseSensitive: false,
      ).hasMatch(message)) {
    return message;
  }
  return fallback;
}
