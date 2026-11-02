import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/features/news/news_screen.dart';

void main() {
  testWidgets('Comment action stays above the keyboard on an article', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(home: NewsScreen(onComment: (_) => false)),
    );
    await tester.pumpAndSettle();
    final title = find.text('Webb, gezegen çarpışmalarının izlerini araştırdı');
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pumpAndSettle();

    final action = find.text('Yorum yap');
    expect(action, findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(action).dy, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
  });
}
