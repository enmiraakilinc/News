import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/features/media/media_names_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:flutter_application_1/core/utils/refresh_stream.dart';
import 'package:flutter_application_1/core/theme/chat_theme.dart';
import 'package:flutter_application_1/features/contacts/contacts_screen.dart';
import 'package:flutter_application_1/features/chat/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'First entry shows conversations while profile and contact sync are still pending',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final profile = Completer<String?>();
      final contacts = Completer<void>();
      var listens = 0;
      final stream = StreamController<List<Conversation>>(
        onListen: () {
          listens++;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ContactsScreen(
            profileLoader: () => profile.future,
            contactLoader: () => contacts.future,
            conversationsLoader: () => stream.stream,
          ),
        ),
      );
      stream.add([
        Conversation(
          id: 'test-chat',
          group: false,
          title: '',
          members: [],
          names: {'friend': 'Defne'},
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Defne'), findsOneWidget);
      expect(find.text('Profil yükleniyor…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      profile.complete('Ben');
      contacts.complete();
      await tester.pumpAndSettle();
      expect(find.text('Defne'), findsOneWidget);
      expect(listens, 1);
      // Finish the real badge's Firebase readiness timeout while still mounted.
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(stream.close);
    },
  );
  testWidgets('Profile failure leaves conversations visible on first entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profile = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(
          profileLoader: () => profile.future,
          contactLoader: () async {},
          conversationsLoader: () => Stream.value([
            Conversation(
              id: 'test-chat',
              group: true,
              title: 'Ders grubu',
              members: [],
              names: {},
            ),
          ]),
        ),
      ),
    );
    profile.completeError(TimeoutException('network'));
    await tester.pumpAndSettle();
    expect(find.text('Ders grubu'), findsOneWidget);
    expect(
      find.text('Profil bilgisi alınamadı; sohbetlerini yine de açabilirsin.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpWidget(const SizedBox());
  });
  for (final video in [false, true]) {
    testWidgets(
      'Multiple ${video ? 'videos' : 'photos'} use one confirmation and cancellation sends nothing',
      (tester) async {
        var sent = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: ChatComposer(
                onSend: (_, _) async {
                  sent++;
                },
                pickGallery: (pickedVideo) async {
                  expect(pickedVideo, video);
                  return [
                    XFile.fromData(
                      Uint8List(10),
                      name: video ? 'one.mp4' : 'one.jpg',
                    ),
                    XFile.fromData(
                      Uint8List(10),
                      name: video ? 'two.mp4' : 'two.jpg',
                    ),
                  ];
                },
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Fotoğraf, video veya konum'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(video ? 'Galeriden video seç' : 'Galeriden fotoğraf seç'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MediaNamesScreen), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(sent, 0);
      },
    );
  }
  testWidgets(
    'Long press copies received message without other actions enabled',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              mine: false,
              text: 'Ders notu\nİkinci satır',
              time: '12:00',
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Ders notu\nİkinci satır'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopyala'));
      await tester.pumpAndSettle();
      expect(copied, 'Ders notu\nİkinci satır');
    },
  );
  testWidgets('Sending keeps focus and preserves edits during delivery', (
    tester,
  ) async {
    final delivery = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatComposer(onSend: (_, _) => delivery.future),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'First');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'Next draft');
    delivery.complete();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Next draft',
    );
  });

  testWidgets('Chat reserves keyboard space once and keeps messages visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    const bodyKey = ValueKey('messages');
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScaffold(
          body: const SizedBox.expand(key: bodyKey),
          bottomNavigationBar: ChatComposer(onSend: (_, _) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(bodyKey)).height, greaterThan(400));
    expect(
      tester.getBottomRight(find.byType(TextField)).dy,
      lessThanOrEqualTo(500),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chat defaults to dark and theme selection is saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    ChatThemes.selected.value = 'dark';
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScaffold(
          appBar: AppBar(actions: const [ChatThemeButton()]),
          body: const Text('Sohbet'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Sohbet'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Sohbet teması'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Sohbet'))).brightness,
      Brightness.light,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('neural_chat_theme'), 'light');
  });
  testWidgets('Composer stays above keyboard and returns after dismissal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: ChatComposer(onSend: (_, _) async {}),
        ),
      ),
    );
    final resting = tester.getBottomRight(find.byType(TextField)).dy;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      tester.getBottomRight(find.byType(TextField)).dy,
      lessThanOrEqualTo(500),
    );
    expect(
      tester.getBottomRight(find.byTooltip('Gönder')).dy,
      lessThanOrEqualTo(500),
    );
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.getBottomRight(find.byType(TextField)).dy, resting);
  });
  testWidgets('Cancelling attachment returns to chat without sending', (
    tester,
  ) async {
    var sent = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            onSend: (_, _) async {
              sent = true;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Taslak');
    await tester.tap(find.byTooltip('Dosya gönder'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Geri dön'), findsOneWidget);
    await tester.tap(find.text('Vazgeç ve geri dön'));
    await tester.pumpAndSettle();
    expect(sent, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Taslak',
    );
  });
  testWidgets('Swipe replies without removing the message', (tester) async {
    var replied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            mine: false,
            text: 'Kaydır',
            time: '12:00',
            onReply: () => replied = true,
          ),
        ),
      ),
    );
    await tester.drag(find.text('Kaydır'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(replied, isTrue);
    expect(find.text('Kaydır'), findsOneWidget);
  });
  testWidgets(
    'Immediate send delegates its time to the server and clears the draft',
    (tester) async {
      String? sent;
      DateTime? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ChatComposer(
              onSend: (text, date) async {
                sent = text;
                opened = date;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Bugün sana bir mektup');
      await tester.tap(find.byTooltip('Gönder'));
      await tester.pump();
      expect(sent, 'Bugün sana bir mektup');
      expect(opened, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('Failed send keeps its text separately for retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatComposer(
            onSend: (text, date) async {
              attempts++;
              throw Exception('offline');
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Kaybolmasın');
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Kaybolmasın'), findsOneWidget);
    expect(find.textContaining('Gönderilemedi'), findsOneWidget);
    await tester.tap(find.text('Tekrar gönder'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Kaybolmasın'), findsOneWidget);
  });

  testWidgets('Reply preview can be cancelled without discarding draft', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatComposer(
            replyPreview: 'Önceki mektup',
            onCancelReply: () => cancelled = true,
            onSend: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Yanıtım');
    await tester.tap(find.byTooltip('Yanıtı kaldır'));
    expect(cancelled, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Yanıtım',
    );
  });

  testWidgets('Long press exposes reply and delete actions', (tester) async {
    var replied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            mine: true,
            text: 'Mektup',
            time: '12:00',
            onReply: () => replied = true,
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.longPress(find.text('Mektup'));
    await tester.pumpAndSettle();
    expect(find.text('Sil'), findsOneWidget);
    await tester.tap(find.text('Yanıtla'));
    await tester.pumpAndSettle();
    expect(replied, isTrue);
  });

  test(
    'Time refresh does not reconnect and stops after cancellation',
    () async {
      var listens = 0;
      var cancels = 0;
      final source = StreamController<int>(
        onListen: () => listens++,
        onCancel: () => cancels++,
      );
      final values = <int>[];
      final second = Completer<void>();
      final subscription =
          refreshStream(
            source.stream,
            interval: const Duration(milliseconds: 10),
          ).listen((value) {
            values.add(value);
            if (values.length == 2 && !second.isCompleted) second.complete();
          });
      source.add(7);
      await second.future.timeout(const Duration(seconds: 2));
      expect(values, [7, 7]);
      expect(listens, 1);
      await subscription.cancel();
      expect(cancels, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(values, [7, 7]);
      unawaited(source.close());
    },
  );
}
