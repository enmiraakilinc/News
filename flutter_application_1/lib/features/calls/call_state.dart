const voiceCallConnectionTimeout = Duration(seconds: 60);
const voiceCallDisconnectGracePeriod = Duration(seconds: 90);
const voiceCallRingDuration = Duration(seconds: 60);

String voiceCallEndMessage(String? reason) => switch (reason) {
  'unanswered' => 'Yanıt alınamadı. Karşı taraf aramayı yanıtlamadı.',
  'rejected' => 'Karşı taraf aramayı reddetti.',
  'caller_cancelled' => 'Arayan aramayı iptal etti.',
  'connection_timeout' =>
    'Yanıtlandı ancak 60 saniye içinde bağlantı kurulamadı. İnternet bağlantısını kontrol edip yeniden dene.',
  'connection_failed' =>
    'Arama bağlantısı kurulamadı. İnternet bağlantısını kontrol edip yeniden dene.',
  'connection_lost' =>
    'Görüşme bağlantısı koptu. İnternet bağlantısını kontrol edip yeniden ara.',
  'setup_failed' =>
    'Arama kurulamadı. İnternet ve mikrofon izinlerini kontrol edip yeniden dene.',
  'account_changed' => 'Hesap değiştiği için arama sona erdi.',
  _ => 'Karşı taraf aramayı bitirdi.',
};

String voiceCallEventText({
  required bool video,
  required String? reason,
  bool answered = false,
}) {
  final outcome = switch (reason) {
    'unanswered' => 'Yanıtlanmadı',
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
