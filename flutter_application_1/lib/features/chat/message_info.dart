// Mesajın gönderilme, iletilme ve okunma zamanlarını tablo olarak gösterir.
import 'package:flutter/material.dart';

class MessageInfoRow {
  final String name;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  const MessageInfoRow(this.name, {this.deliveredAt, this.readAt});
}

class MessageInfo {
  final DateTime? sentAt;
  final List<MessageInfoRow> rows;
  const MessageInfo({required this.sentAt, required this.rows});
}

String _two(int value) => value.toString().padLeft(2, '0');

String messageInfoTime(DateTime? value) => value == null
    ? '—'
    : '${_two(value.day)}.${_two(value.month)}.${value.year} '
          '${_two(value.hour)}:${_two(value.minute)}';

Future<void> showMessageInfo(BuildContext context, MessageInfo info) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        Widget cell(String text, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        );
        return AlertDialog(
          title: const Text('Mesaj bilgisi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gönderildi: ${messageInfoTime(info.sentAt)}'),
                const SizedBox(height: 12),
                Table(
                  border: TableBorder.all(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        cell('Kişi', bold: true),
                        cell('✓ İletildi', bold: true),
                        cell('✓✓ Okundu', bold: true),
                      ],
                    ),
                    for (final row in info.rows)
                      TableRow(
                        children: [
                          cell(row.name),
                          cell(messageInfoTime(row.deliveredAt ?? row.readAt)),
                          cell(messageInfoTime(row.readAt)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
