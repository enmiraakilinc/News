// Aramanın durumunu ve neden bittiğini tutar.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

const voiceCallConnectionTimeout = Duration(seconds: 60);
const voiceCallDisconnectGracePeriod = Duration(seconds: 90);
const voiceCallRingDuration = Duration(seconds: 60);

const voiceCallTerminalReasons = {
  'unanswered',
  'rejected',
  'caller_cancelled',
  'call_ended',
  'connection_timeout',
  'connection_failed',
  'connection_lost',
  'setup_failed',
  'account_changed',
};

String voiceCallEndMessage(String? reason) => switch (reason) {
  'unanswered' => 'Karşı taraf aramayı yanıtlamadı.',
  'rejected' => 'Karşı taraf aramayı reddetti.',
  'caller_cancelled' => 'Arayan aramayı iptal etti.',
  'connection_timeout' =>
    'Arama zaman aşımına uğradı. 60 saniye içinde bağlantı kurulamadı.',
  'connection_failed' || 'connection_lost' => 'Karşı tarafın bağlantısı koptu.',
  'setup_failed' =>
    'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.',
  'account_changed' => 'Hesap değiştiği için arama sona erdi.',
  'call_ended' => 'Karşı taraf aramayı bitirdi.',
  _ => 'Karşı taraf aramayı bitirdi.',
};

String voiceCallEventText({
  required bool video,
  required String? reason,
  bool answered = false,
}) {
  final outcome = switch (reason) {
    'unanswered' => 'Cevapsız',
    'rejected' => 'Reddedildi',
    'caller_cancelled' => 'Arayan aramayı iptal etti',
    'connection_timeout' => 'Yanıtlandı · bağlantı kurulamadı',
    'connection_failed' => 'Yanıtlandı · bağlantı kurulamadı',
    'connection_lost' => 'Yanıtlandı · bağlantı koptu',
    'setup_failed' => answered
        ? 'Yanıtlandı · arama kurulamadı'
        : 'Arama kurulamadı',
    'account_changed' => answered
        ? 'Yanıtlandı · hesap değişti'
        : 'Hesap değişti',
    'answered' => 'Yanıtlandı',
    'call_ended' => answered ? 'Yanıtlandı' : 'Arama sona erdi',
    _ => answered ? 'Yanıtlandı' : 'Arama sona erdi',
  };
  return '📞 ${video ? 'Görüntülü' : 'Sesli'} arama · $outcome';
}

String voiceCallFailureMessage(Object error, {required bool video}) {
  if (error is TimeoutException || error is SocketException) {
    return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
  }
  final raw = error.toString().toLowerCase();
  if (error is FirebaseException ||
      raw.contains('permission-denied') ||
      raw.contains('permission_denied')) {
    final code = error is FirebaseException ? error.code : raw;
    if (code == 'unavailable' ||
        code == 'network-request-failed' ||
        raw.contains('unavailable') ||
        raw.contains('network') ||
        raw.contains('socket')) {
      return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
    }
    if (code == 'permission-denied' ||
        raw.contains('permission-denied') ||
        raw.contains('permission_denied') ||
        raw.contains('erişim iznin yok')) {
      return 'Sunucu/sinyalleşme izni reddedildi (oturum veya kural yetkisi eksik).';
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'not-found' => 'Arama kaydı bulunamadı veya süresi doldu.',
        'unauthenticated' =>
          'Hesap oturumun doğrulanamadı. Hesabına yeniden giriş yapıp dene.',
        'deadline-exceeded' =>
          'Arama zaman aşımına uğradı. Sunucu yanıt vermedi.',
        'resource-exhausted' =>
          'Hizmetin kullanım sınırına ulaşıldı. Daha sonra yeniden dene.',
        _ => 'Sunucu aramayı tamamlayamadı. Biraz sonra yeniden dene.',
      };
    }
  }
  if (error is PlatformException || raw.contains('permission') || raw.contains('in_use')) {
    final blob = error is PlatformException
        ? '${error.code} ${error.message ?? ''} ${error.details ?? ''}'.toLowerCase()
        : raw;
    if (blob.contains('in_use') ||
        blob.contains('inuse') ||
        blob.contains('notreadable') ||
        blob.contains('not_readable') ||
        blob.contains('busy')) {
      return 'Mikrofon/kamera başka bir uygulama tarafından kullanılıyor.';
    }
    if (blob.contains('camera') &&
        (blob.contains('permission') ||
            blob.contains('denied') ||
            blob.contains('access'))) {
      return 'Kamera izni kapalı, ayarlardan izin verin.';
    }
    if (blob.contains('permission') ||
        blob.contains('denied') ||
        blob.contains('notauthorized') ||
        blob.contains('access_denied')) {
      return video
          ? 'Kamera izni kapalı, ayarlardan izin verin.'
          : 'Mikrofon izni kapalı, ayarlardan izin verin.';
    }
  }
  if (raw.contains('erişim iznin yok') || raw.contains('permission-denied')) {
    return 'Sunucu/sinyalleşme izni reddedildi (oturum veya kural yetkisi eksik).';
  }
  if (raw.contains('sona ermiş')) {
    return 'Karşı taraf aramayı yanıtladıktan sonra kayıt kapanmış.';
  }
  if (raw.contains('rejected')) {
    return 'Karşı taraf aramayı reddetti.';
  }
  if (raw.contains('unanswered') || raw.contains('timeout') || raw.contains('deadline')) {
    return 'Arama zaman aşımına uğradı. Karşı taraf yanıt vermedi.';
  }
  if (raw.contains('connection_lost') || raw.contains('disconnected')) {
    return 'Karşı tarafın bağlantısı koptu.';
  }
  final visible = error.toString().replaceFirst('Exception: ', '').trim();
  if (visible.isNotEmpty && visible.length < 200) return visible;
  return 'İnternet bağlantınız çok yavaş veya kesildi, arama kurulamadı.';
}
