import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import '../../core/utils/user_errors.dart';
import 'chat_media.dart';

Future<void> extendChatAttachment(BuildContext context, String message) async {
  try {
    final id = ChatMedia.idFrom(message);
    final data = await ChatMedia.expiryInfo(id);
    if (!context.mounted) return;
    if (data['owner'] != CoupleService.uid) {
      throw Exception('Süreyi yalnızca dosyayı gönderen uzatabilir.');
    }
    final expiry = chatMediaExpiresAt(data);
    final now = DateTime.now();
    if (!expiry.isAfter(now)) {
      throw Exception('Dosyanın süresi dolmuş. Silinmeden önce uzatmalısın.');
    }
    final day = await showDatePicker(
      context: context,
      helpText: 'Erişimi hangi tarihe kadar uzatalım?',
      initialDate: expiry,
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateTime(2100, 12, 31),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'Erişimin biteceği saat',
      initialTime: TimeOfDay.fromDateTime(expiry),
    );
    if (time == null || !context.mounted) return;
    final until = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (!until.isAfter(expiry)) {
      throw Exception('Mevcut süreden daha ileri bir tarih ve saat seç.');
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erişim süresini uzat'),
        content: Text(
          'Bu dosya ${MaterialLocalizations.of(ctx).formatFullDate(until)} '
          '${MaterialLocalizations.of(ctx).formatTimeOfDay(TimeOfDay.fromDateTime(until))} tarihine kadar saklanacak. '
          'İstersen süre dolmadan tekrar uzatabilirsin. Dosya bu süre boyunca sunucuda yer kullanır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uzat'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await ChatMedia.extendUntil(id, until);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dosyanın erişim süresi uzatıldı.')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userError(error, fallback: 'Süre uzatılamadı. Yeniden dene.'),
          ),
        ),
      );
    }
  }
}
