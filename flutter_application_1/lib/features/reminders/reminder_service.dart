import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/notifications/notification_permission.dart';
import '../../core/utils/user_errors.dart';

class ReminderService {
  static const channel = MethodChannel('app/reminders');
  static Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});
  static Future<bool> fullScreenAccess(BuildContext context) async {
    const wake = MethodChannel('app/wakeup');
    if (await wake.invokeMethod<bool>('fullScreenAllowed') == true) return true;
    if (!context.mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tam ekran alarm izni'),
        content: const Text(
          'Alarmı kilit ekranında tam ekran göstermek için Android özel erişim izni gerekiyor. İzni verdikten sonra işlemi tekrar başlat. İzin ekranını açalım mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Şimdi değil'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İzni aç'),
          ),
        ],
      ),
    );
    if (open == true) await wake.invokeMethod('fullScreenSettings');
    return false;
  }

  static Future<void> pick(BuildContext context, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('personal_reminders_enabled') == false) {
        if (!context.mounted) return;
        final enable = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Not hatırlatıcılarını aç?'),
            content: const Text(
              'Kişisel hatırlatıcıların kapalı. Yalnızca bu özelliği açalım mı? Sohbet bildirimleri değişmez.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Aç'),
              ),
            ],
          ),
        );
        if (enable != true) return;
      }
      if (!context.mounted) return;
      if (!await ensureNotificationPermission(context) || !context.mounted) {
        return;
      }
      if (!await fullScreenAccess(context) || !context.mounted) return;
      if (await channel.invokeMethod<bool>('canSchedule') != true) {
        if (!context.mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Alarm zamanlama izni'),
            content: const Text(
              'Notunu seçtiğin saatte hatırlatmak için Alarmlar ve hatırlatıcılar izni gerekiyor. İzni açtıktan sonra hatırlatıcıyı yeniden kur.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('İzni aç'),
              ),
            ],
          ),
        );
        if (open == true) await channel.invokeMethod('settings');
        return;
      }
      if (!context.mounted) return;
      final now = DateTime.now();
      final day = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 365)),
      );
      if (day == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          now.add(const Duration(minutes: 1)),
        ),
      );
      if (time == null) return;
      final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!at.isAfter(DateTime.now())) throw Exception('İleri bir saat seç.');
      await prefs.setBool('personal_reminders_enabled', true);
      await channel.invokeMethod('schedule', {
        'id': id,
        'at': at.millisecondsSinceEpoch,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hatırlatıcı: ${at.day}.${at.month}.${at.year} ${time.format(context)}',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback: 'Hatırlatıcı kurulamadı. İzinleri kontrol et.',
              ),
            ),
          ),
        );
      }
    }
  }
}
