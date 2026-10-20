import 'package:flutter/material.dart';
import '../features/account/chat_account.dart';
import '../core/theme/chat_theme.dart';
import '../features/calls/voice_call.dart';
import '../features/startup/startup_gate.dart';

import 'app_runtime.dart';
import '../features/home/entry_screen.dart';

class SystemGalleryApp extends StatelessWidget {
  const SystemGalleryApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: ChatThemes.selected,
      builder: (_, value, child) => ValueListenableBuilder<int>(
        valueListenable: ChatAccount.revision,
        builder: (_, revision, child) => MaterialApp(
          key: ValueKey(revision),
          navigatorKey: appNavigatorKey,
          builder: (context, child) =>
              VoiceCallInbox(navigator: appNavigatorKey, child: child!),
          debugShowCheckedModeBanner: false,
          title: 'Neural Haber',
          theme: ChatThemes.theme(value),
          home: StartupGate(
            initialize: initializeLocalNotifications,
            child: const FakeGalleryPage(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  ANA SAYFA
// ─────────────────────────────────────────
