import 'package:flutter_application_1/features/calls/call_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unanswered and rejected calls have distinct explanations', () {
    expect(voiceCallEndMessage('unanswered'), contains('yanıtlamadı'));
    expect(voiceCallEndMessage('rejected'), contains('reddetti'));
    expect(
      voiceCallEndMessage('unanswered'),
      isNot(voiceCallEndMessage('rejected')),
    );
  });

  test('conversation events are limited to missed and rejected calls', () {
    expect(
      voiceCallEventText(video: false, reason: 'unanswered'),
      '📞 Sesli arama · Yanıtlanmadı',
    );
    expect(
      voiceCallEventText(video: true, reason: 'rejected'),
      '📞 Görüntülü arama · Reddedildi',
    );
    expect(voiceCallEventText(video: false, reason: 'call_ended'), isNull);
    expect(
      voiceCallEventText(video: false, reason: 'caller_cancelled'),
      isNull,
    );
  });

  test('connection failures explain timeout, failure, and dropped calls', () {
    expect(voiceCallEndMessage('connection_timeout'), contains('60 saniye'));
    expect(voiceCallEndMessage('connection_failed'), contains('kurulamadı'));
    expect(voiceCallEndMessage('connection_lost'), contains('koptu'));
  });

  test('connection timers leave room for setup and brief network recovery', () {
    expect(voiceCallConnectionTimeout, const Duration(seconds: 60));
    expect(voiceCallDisconnectGracePeriod, const Duration(seconds: 30));
    expect(voiceCallRingDuration, const Duration(seconds: 60));
  });

  test(
    'missed-call message preference is scoped to each conversation',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await callEventMessagesEnabled('chat/first'), isTrue);
      await setCallEventMessagesEnabled('chat/first', false);
      expect(await callEventMessagesEnabled('chat/first'), isFalse);
      expect(await callEventMessagesEnabled('chat/second'), isTrue);
    },
  );
}
