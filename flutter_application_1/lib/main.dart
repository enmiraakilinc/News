import 'dart:async';
import 'package:flutter/material.dart';
import 'app/app_shell.dart';
import 'app/app_runtime.dart';
export 'app/app_shell.dart';
export 'app/app_runtime.dart';
export 'features/home/entry_screen.dart';
export 'features/home/private_home.dart';
export 'features/tools/tools_screen.dart';
export 'features/media/full_image_screen.dart';

// Keep this library/name stable for existing WorkManager callback handles.
@pragma('vm:entry-point')
void callbackDispatcher() => runBackgroundDispatcher();
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SystemGalleryApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(initializeBackground(callbackDispatcher));
  });
}
