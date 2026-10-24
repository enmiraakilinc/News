import 'package:flutter_application_1/features/calls/call_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/src/native/media_stream_track_impl.dart';
import 'package:flutter_application_1/features/calls/call_controls.dart';
import 'package:flutter_application_1/features/calls/call_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Voice controls stay independent and fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var mic = false, speaker = false, receive = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => CallControls(
              muted: mic,
              speakerOn: speaker,
              receiveMuted: receive,
              video: false,
              cameraOff: false,
              audioBusy: false,
              enabled: true,
              onMicrophone: () => update(() => mic = !mic),
              onSpeaker: () => update(() => speaker = !speaker),
              onReceive: () => update(() => receive = !receive),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Mikrofonu kapat'));
    await tester.pump();
    expect(mic, isTrue);
    expect(speaker, isFalse);
    expect(receive, isFalse);
    await tester.tap(find.byTooltip('Hoparlörü aç'));
    await tester.pump();
    expect(speaker, isTrue);
    await tester.tap(find.byTooltip('Karşı tarafın sesini kapat'));
    await tester.pump();
    expect(receive, isTrue);
    expect(find.byTooltip('Karşı tarafın sesini aç'), findsOneWidget);
    expect(find.text('Kamera'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Video keeps camera and microphone available during audio changes',
    (tester) async {
      var microphone = 0, camera = 0, switches = 0, routes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              muted: false,
              speakerOn: true,
              receiveMuted: false,
              video: true,
              cameraOff: false,
              audioBusy: true,
              enabled: true,
              onMicrophone: () => microphone++,
              onSpeaker: () => routes++,
              onReceive: () => routes++,
              onCamera: () => camera++,
              onSwitchCamera: () => switches++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Mikrofonu kapat'));
      await tester.tap(find.byTooltip('Kamerayı kapat'));
      await tester.tap(find.byTooltip('Kamerayı değiştir'));
      final speaker = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.volume_up),
      );
      final receive = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.headphones),
      );
      expect(speaker.onPressed, isNull);
      expect(receive.onPressed, isNull);
      expect([microphone, camera, switches, routes], [1, 1, 1, 0]);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Receive mute changes remote audio, preserving local mic and remote video',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('FlutterWebRTC.Method');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final incoming = MediaStreamTrackNative(
        'remote-audio',
        '',
        'audio',
        true,
        'peer',
      );
      final video = MediaStreamTrackNative(
        'remote-video',
        '',
        'video',
        true,
        'peer',
      );
      final local = MediaStreamTrackNative(
        'local-mic',
        '',
        'audio',
        true,
        'local',
      );
      await setCallReceiveMuted([incoming, video], true);
      expect(incoming.enabled, isFalse);
      expect(video.enabled, isTrue);
      expect(local.enabled, isTrue);
      expect(calls.where((c) => c.method == 'setVolume').single.arguments, {
        'trackId': 'remote-audio',
        'volume': 0,
        'peerConnectionId': 'peer',
      });
      await setCallReceiveMuted([incoming, video], false);
      expect(incoming.enabled, isTrue);
      expect(
        calls.where((c) => c.method == 'setVolume').last.arguments['volume'],
        1,
      );
      expect(
        calls
            .where((c) => c.arguments is Map && c.arguments['trackId'] != null)
            .every((c) => c.arguments['trackId'] == 'remote-audio'),
        isTrue,
      );
    },
  );
  test(
    'An active call starts its foreground service without requesting notification permission',
    () async {
      const channel = MethodChannel('app/voice_call');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await CallBackground.start('active-call', video: true), isTrue);
      await CallBackground.connected('active-call');
      expect(calls.map((c) => c.method), ['start', 'connected']);
      expect(calls.last.arguments, {'id': 'active-call'});
    },
  );
}
