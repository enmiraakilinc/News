import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/features/news/news_notes.dart';
import 'package:flutter_application_1/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/news/news_screen.dart';
import 'package:flutter_application_1/core/theme/news_theme.dart';
import 'package:flutter_application_1/core/theme/chat_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NewsThemes.selected.value = 'dark';
  });
  testWidgets(
    'Dedicated voice notes show only audio without removing other personal notes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'personal_media_notes': [
          jsonEncode({
            'id': 'audio',
            'kind': 'audio',
            'file': '123_0.m4a',
            'title': 'Ders kaydım',
          }),
          jsonEncode({
            'id': 'text',
            'kind': 'text',
            'text': 'Gizlenmez, sadece filtrelenir',
            'title': 'Yazılı notum',
          }),
        ],
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewsNotes(article: 0, audioOnly: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sesli Notlarım'), findsOneWidget);
      expect(find.text('Ders kaydım'), findsOneWidget);
      expect(find.text('Yazılı notum'), findsNothing);
      expect(find.text('Yazılı not'), findsNothing);
      expect(find.text('Konum ekle'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'personal_media_notes',
        ),
        hasLength(2),
      );
      expect(
        ChatThemes.theme('orange').colorScheme.primary,
        const Color(0xfffc9803),
      );
    },
  );

  testWidgets(
    'Personal text notes save, reload and edit without losing their reminder ID',
    (tester) async {
      Future<void> open() async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NewsNotes(article: 1))),
        );
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Yazılı not'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Ders planım');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Önce tokenizer konusunu çalış.',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final original =
          jsonDecode(prefs.getStringList('personal_media_notes')!.single)
              as Map;
      expect(original['id'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await open();
      expect(find.text('Ders planım'), findsOneWidget);
      expect(find.text('Alarm kur'), findsOneWidget);
      await tester.tap(find.text('Ders planım'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Parse konusunu da ekle.',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      final edited =
          jsonDecode(prefs.getStringList('personal_media_notes')!.single)
              as Map;
      expect(edited['id'], original['id']);
      expect(edited['text'], 'Parse konusunu da ekle.');
    },
  );
  testWidgets(
    'Visible note alarm button opens the required alarm permission flow',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'personal_media_notes': [
          jsonEncode({
            'id': 'note-1',
            'kind': 'text',
            'title': 'Ders',
            'text': 'Çalış',
          }),
        ],
      });
      final calls = <String>[];
      const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
      const wake = MethodChannel('app/wakeup');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(plugin, (_) async => true);
      messenger.setMockMethodCallHandler(wake, (_) async => true);
      messenger.setMockMethodCallHandler(ReminderService.channel, (call) async {
        calls.add(call.method);
        return call.method == 'canSchedule' ? false : null;
      });
      addTearDown(() {
        for (final channel in [plugin, wake, ReminderService.channel]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NewsNotes(article: 1))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alarm kur'));
      await tester.pumpAndSettle();
      expect(find.text('Alarm zamanlama izni'), findsOneWidget);
      expect(calls, ['canSchedule']);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('Public theme changes immediately and saves independently', (
    tester,
  ) async {
    final privateTheme = ChatThemes.selected.value;
    await tester.pumpWidget(
      MaterialApp(home: NewsScreen(onComment: (_) => false)),
    );
    await tester.pumpAndSettle();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tema'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Açık'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Gündeme bir bakış'))).brightness,
      Brightness.light,
    );
    expect(ChatThemes.selected.value, privateTheme);
    expect(
      (await SharedPreferences.getInstance()).getString('neural_news_theme'),
      'light',
    );
    await tester.tap(
      find.text('Webb, gezegen çarpışmalarının izlerini araştırdı'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(TextField), 300);
    expect(
      Theme.of(tester.element(find.byType(TextField))).brightness,
      Brightness.light,
    );
  });
  testWidgets('Public news and its drawer do not expose private settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NewsScreen(onComment: (_) => false)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ayarlar'), findsNothing);
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsNothing);
    expect(find.text('Haber bildirimleri'), findsNothing);
    expect(find.text('Kendime Notlar'), findsOneWidget);
    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Ders Notlarım'), findsOneWidget);
    await tester.tap(find.text('Haber ve hatırlatıcı ayarları'));
    await tester.pumpAndSettle();
    expect(find.text('Haberler'), findsOneWidget);
    expect(find.text('Not hatırlatıcıları'), findsOneWidget);
    expect(find.text('Uyandırma alarmları'), findsNothing);
    expect(find.text('Sohbetler'), findsNothing);
  });
  testWidgets(
    'Category filtering opens the correct article and keeps its comments',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'neural_comments_1': ['Uzay yorumu'],
      });
      await tester.pumpWidget(
        MaterialApp(home: NewsScreen(onComment: (_) => false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Uzay'));
      await tester.pumpAndSettle();
      expect(
        find.text('Webb, gezegen çarpışmalarının izlerini araştırdı'),
        findsNothing,
      );
      final spaceTitle = find.text(
        'James Webb’in ilk görüntüleri evrene yeni bir pencere açtı',
      );
      expect(spaceTitle, findsOneWidget);
      await tester.tap(spaceTitle);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Uzay yorumu'), 300);
      expect(find.text('Uzay yorumu'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tümü'));
      await tester.pumpAndSettle();
      expect(
        find.text('Webb, gezegen çarpışmalarının izlerini araştırdı'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Haber ve yorum ekranı açık uygulama temasında da karanlık kalır',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: NewsScreen(onComment: (_) => false),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Gündeme bir bakış'))).brightness,
        Brightness.dark,
      );
      await tester.tap(
        find.text('Webb, gezegen çarpışmalarının izlerini araştırdı'),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(TextField), 300);
      expect(
        Theme.of(tester.element(find.byType(TextField))).brightness,
        Brightness.dark,
      );
    },
  );
  Future<void> openArticle(
    WidgetTester tester,
    bool Function(String) submit,
  ) async {
    await tester.pumpWidget(MaterialApp(home: NewsScreen(onComment: submit)));
    await tester.tap(
      find.text('Webb, gezegen çarpışmalarının izlerini araştırdı'),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(TextField), 300);
  }

  testWidgets('Normal yorum kaydedilir', (tester) async {
    await openArticle(tester, (_) => false);
    await tester.enterText(find.byType(TextField), 'Güzel bir yazı');
    await tester.ensureVisible(find.text('Yorum gönder'));
    await tester.tap(find.text('Yorum gönder'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('neural_comments_0'), ['Güzel bir yazı']);
  });
  testWidgets('Yorum düzenlenir ve silinir; değişiklikler kaydedilir', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'neural_comments_0': ['Eski yorum'],
    });
    await openArticle(tester, (_) => false);
    await tester.ensureVisible(find.byTooltip('Yorum seçenekleri'));
    await tester.tap(find.byTooltip('Yorum seçenekleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Yeni yorum',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('neural_comments_0'), ['Yeni yorum']);
    await tester.tap(find.byTooltip('Yorum seçenekleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('neural_comments_0'), isEmpty);
  });
  for (final pin in ['1703', '0000']) {
    testWidgets('$pin kaydedilmeden girişe iletilir', (tester) async {
      String? received;
      await openArticle(tester, (value) {
        received = value;
        return value == pin;
      });
      await tester.enterText(find.byType(TextField), pin);
      await tester.ensureVisible(find.text('Yorum gönder'));
      await tester.tap(find.text('Yorum gönder'));
      await tester.pumpAndSettle();
      expect(received, pin);
      expect(find.byType(TextField), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('neural_comments_0'), isNull);
    });
  }
}
