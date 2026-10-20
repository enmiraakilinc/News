import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Ask at the point of use; never enable a preference after a denied grant.
Future<bool> ensureNotificationPermission(BuildContext context) async {
  final android = FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return true;
  if (await android.areNotificationsEnabled() == true) return true;
  if (!context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Bildirim izni gerekli'),
      content: const Text(
        'Bu özellik için telefonun bildirim iznini açmalısın. Diğer özelliklerin bildirimleri kendi seçimlerine göre kapalı kalır.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Şimdi değil'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('İzin ver'),
        ),
      ],
    ),
  );
  if (proceed != true) return false;
  if (await android.requestNotificationsPermission() == true) return true;
  if (!context.mounted) return false;
  final settings = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Telefon ayarlarından aç'),
      content: const Text(
        'Bildirim izni kapalı. Doğrudan bu uygulamanın bildirim ayarlarını açalım mı? Açtıktan sonra buradaki seçeneği tekrar etkinleştirebilirsin.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Bildirim ayarları'),
        ),
      ],
    ),
  );
  if (settings == true) {
    await const MethodChannel(
      'app/permissions',
    ).invokeMethod('notificationSettings');
  }
  return false;
}
