const voiceCallConnectionTimeout = Duration(seconds: 60);
const voiceCallDisconnectGracePeriod = Duration(seconds: 12);

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

String? voiceCallEventText({required bool video, required String? reason}) {
  final outcome = switch (reason) {
    'unanswered' => 'Yanıtlanmadı',
    'rejected' => 'Reddedildi',
    _ => null,
  };
  if (outcome == null) return null;
  return '📞 ${video ? 'Görüntülü' : 'Sesli'} arama · $outcome';
}
