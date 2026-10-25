import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/theme/chat_theme.dart';
import 'package:flutter_application_1/features/chat/chat_widgets.dart';
import 'package:flutter_application_1/features/chat/conversation_style.dart';
import 'package:flutter_application_1/features/contacts/contact_details_screen.dart';
import 'package:flutter_application_1/features/contacts/profile_avatar.dart';

void main() {
  testWidgets(
    'Press feedback preserves one action and respects reduced motion',
    (tester) async {
      for (final reduced in [false, true]) {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: ConversationPressFeedback(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('Gönder'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Gönder')),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduced ? 1 : .96,
        );
        expect(taps, 0);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          1,
        );
        expect(tester.binding.transientCallbackCount, 0);
      }
    },
  );

  testWidgets(
    'Long settings remain visible with large text and small corners',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const label = 'Karşı tarafın beni kaydettiği isim ve bildirim tercihleri';
      await tester.pumpWidget(
        MaterialApp(
          theme: ChatThemes.conversationTheme('purple'),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ConversationSection(
                    children: [
                      SwitchListTile(
                        value: true,
                        onChanged: (_) {},
                        title: const Text(label),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, false);
      final textRect = tester.getRect(find.text(label));
      final sectionRect = tester.getRect(find.byType(ConversationSection));
      expect(sectionRect.contains(textRect.topLeft), true);
      expect(sectionRect.contains(textRect.bottomRight), true);
      expect(tester.takeException(), isNull);
    },
  );

  test('Conversation text has readable contrast in all ten themes', () {
    double contrast(Color a, Color b) {
      final first = a.computeLuminance(), second = b.computeLuminance();
      return first > second
          ? (first + .05) / (second + .05)
          : (second + .05) / (first + .05);
    }

    for (final name in ChatThemes.names.keys) {
      final scheme = ChatThemes.conversationTheme(name).colorScheme;
      final incoming = ConversationColors(scheme).received;
      expect(
        incoming,
        isNot(scheme.surface),
        reason: '$name visible incoming bubble',
      );
      expect(contrast(incoming, scheme.onSurface), greaterThanOrEqualTo(4.5));
      expect(
        ChatThemes.conversationTheme(name).textTheme.bodyMedium!.color,
        scheme.onSurface,
        reason: '$name inherited text',
      );
      expect(
        contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: '$name sent',
      );
      expect(
        contrast(scheme.surfaceContainerLowest, scheme.onSurface),
        greaterThanOrEqualTo(4.5),
        reason: '$name received',
      );
    }
  });

  testWidgets('Narrow conversation and action menu work across all themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preview = Platform.environment['CHAT_PREVIEW_DIR'];
    if (preview != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('PreviewUI')
          ..addFont(
            File(
              'C:/Windows/Fonts/arial.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              'C:/Users/mkund/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await icons.load();
        final emoji = FontLoader('PreviewEmoji')
          ..addFont(
            File(
              'C:/Windows/Fonts/seguiemj.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await emoji.load();
      });
    }
    final key = GlobalKey();
    Future<void> screenshot(String name) async {
      if (preview == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(preview).create(recursive: true);
        await File(
          '$preview/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final name in ChatThemes.names.keys) {
      String? reaction;
      var theme = ChatThemes.conversationTheme(name);
      if (preview != null) {
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(
            fontFamily: 'PreviewUI',
            fontFamilyFallback: ['PreviewEmoji'],
          ),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle!.copyWith(
              fontFamily: 'PreviewUI',
            ),
          ),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: const ContactChatHeader(
                  contactId: 'preview',
                  fallbackName: 'Defne',
                  sourceKey: 'chat/preview',
                ),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Center(child: Chip(label: Text('Bugün'))),
                  const SizedBox(height: 18),
                  const MessageBubble(
                    mine: false,
                    text:
                        'Ders notlarını düzenledim, akşam birlikte bakalım mı?',
                    time: '09:42',
                  ),
                  MessageBubble(
                    mine: true,
                    text: 'Olur, ben de örnek kodları ekledim.',
                    quoted: 'Akşam birlikte bakalım mı?',
                    time: '09:44',
                    onReply: () {},
                    onEdit: () {},
                    onDelete: () {},
                    onReact: (value) => reaction = value,
                  ),
                ],
              ),
              bottomNavigationBar: ChatComposer(
                onSend: (_, _) async {},
                onShareLocation: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      expect(
        tester.getRect(find.byType(ContactAvatar)).right,
        lessThan(tester.getRect(find.text('Defne')).left),
      );
      await screenshot('conversation_$name');
      await tester.longPress(find.text('Olur, ben de örnek kodları ekledim.'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$name menu');
      await screenshot('actions_$name');
      await tester.tap(find.byTooltip('❤️ ifadesini bırak'));
      await tester.pumpAndSettle();
      expect(reaction, '❤️');
      await tester.tap(find.byTooltip('Fotoğraf, video veya konum'));
      await tester.pumpAndSettle();
      expect(find.text('Galeriden video seç'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$name media');
      await screenshot('media_$name');
      await tester.tapAt(const Offset(12, 100));
      await tester.pumpAndSettle();
    }
  });
}
