import 'package:flutter_application_1/features/calls/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unanswered and rejected calls have distinct explanations', () {
    expect(voiceCallEndMessage('unanswered'), contains('yanıtlamadı'));
    expect(voiceCallEndMessage('rejected'), contains('reddetti'));
    expect(
      voiceCallEndMessage('unanswered'),
      isNot(voiceCallEndMessage('rejected')),
    );
  });

  test('every call outcome is recorded in its conversation', () {
    expect(
      voiceCallEventText(video: false, reason: 'unanswered'),
      '📞 Sesli arama · Yanıtlanmadı',
    );
    expect(
      voiceCallEventText(video: true, reason: 'rejected'),
      '📞 Görüntülü arama · Reddedildi',
    );
    expect(
      voiceCallEventText(video: false, reason: 'caller_cancelled'),
      '📞 Sesli arama · Arayan aramayı iptal etti',
    );
    expect(
      voiceCallEventText(video: false, reason: 'call_ended', answered: true),
      '📞 Sesli arama · Yanıtlandı',
    );
    expect(
      voiceCallEventText(
        video: true,
        reason: 'connection_lost',
        answered: true,
      ),
      '📞 Görüntülü arama · Yanıtlandı · bağlantı koptu',
    );
  });

  test('connection failures explain timeout, failure, and dropped calls', () {
    expect(voiceCallEndMessage('connection_timeout'), contains('60 saniye'));
    expect(voiceCallEndMessage('connection_failed'), contains('kurulamadı'));
    expect(voiceCallEndMessage('connection_lost'), contains('koptu'));
  });

  test('connection timers leave room for setup and brief network recovery', () {
    expect(voiceCallConnectionTimeout, const Duration(seconds: 60));
    expect(voiceCallDisconnectGracePeriod, const Duration(seconds: 90));
    expect(voiceCallRingDuration, const Duration(seconds: 60));
  });
}
