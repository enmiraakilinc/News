import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String formatDateInput(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

DateTime? parseDateInput(String text) {
  final parts = text.trim().split(RegExp(r'[/\.\-]'));
  int? day, month, year;
  if (parts.length == 3) {
    final yearFirst = parts.first.length == 4;
    day = int.tryParse(parts[yearFirst ? 2 : 0]);
    month = int.tryParse(parts[1]);
    year = int.tryParse(parts[yearFirst ? 0 : 2]);
  } else {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;
    // Prefer the advertised day/month/year order. Fall back to ISO on paste.
    final possibleMonth = int.parse(digits.substring(2, 4));
    final yearFirst = possibleMonth > 12 || possibleMonth == 0;
    day = int.parse(digits.substring(yearFirst ? 6 : 0, yearFirst ? 8 : 2));
    month = int.parse(digits.substring(yearFirst ? 4 : 2, yearFirst ? 6 : 4));
    year = int.parse(digits.substring(yearFirst ? 0 : 4, yearFirst ? 4 : 8));
  }
  if (day == null || month == null || year == null || year < 1000) return null;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

class DateInputFormatter extends TextInputFormatter {
  const DateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    // Complete dates pasted with dots, dashes or single-digit days/months.
    final parsed = parseDateInput(newValue.text);
    if (parsed != null && newValue.text.length - oldValue.text.length > 1) {
      final text = formatDateInput(parsed);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    var digitCursor = newValue.text
        .substring(
          0,
          newValue.selection.extentOffset.clamp(0, newValue.text.length),
        )
        .replaceAll(RegExp(r'\D'), '')
        .length;
    // Backspace over an inserted separator also removes the preceding digit.
    if (newValue.text.length < oldValue.text.length &&
        digits == oldValue.text.replaceAll(RegExp(r'\D'), '') &&
        digitCursor > 0) {
      digits =
          digits.substring(0, digitCursor - 1) + digits.substring(digitCursor);
      digitCursor--;
    }
    if (digits.length > 8) digits = digits.substring(0, 8);
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    final cursor =
        (digitCursor + (digitCursor > 2 ? 1 : 0) + (digitCursor > 4 ? 1 : 0))
            .clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}

Future<DateTime?> pickDate({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _DateDialog(
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
  ),
);

class _DateDialog extends StatefulWidget {
  final DateTime initialDate, firstDate, lastDate;
  const _DateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  late DateTime _selected = DateUtils.dateOnly(widget.initialDate);
  late final _text = TextEditingController(text: formatDateInput(_selected));
  final _form = GlobalKey<FormState>();
  bool _manual = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    final date = parseDateInput(text ?? '');
    if (date == null) return 'Geçerli bir tarih yaz: GG/AA/YYYY';
    if (date.isBefore(DateUtils.dateOnly(widget.firstDate)) ||
        date.isAfter(DateUtils.dateOnly(widget.lastDate))) {
      return '${formatDateInput(widget.firstDate)} – ${formatDateInput(widget.lastDate)} arasında seç.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Tarih seç')),
        IconButton(
          tooltip: _manual ? 'Takvimden seç' : 'Tarihi elle gir',
          icon: Icon(_manual ? Icons.calendar_month : Icons.edit_outlined),
          onPressed: () => setState(() {
            if (_manual) {
              final date = parseDateInput(_text.text);
              if (_validate(_text.text) == null) _selected = date!;
            } else {
              _text.text = formatDateInput(_selected);
            }
            _manual = !_manual;
          }),
        ),
      ],
    ),
    content: SizedBox(
      width: 320,
      child: _manual
          ? Form(
              key: _form,
              child: TextFormField(
                controller: _text,
                autofocus: true,
                keyboardType: TextInputType.datetime,
                inputFormatters: const [DateInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Tarih',
                  hintText: 'GG/AA/YYYY',
                ),
                validator: _validate,
              ),
            )
          : CalendarDatePicker(
              initialDate: _selected,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (date) => _selected = date,
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () {
          if (_manual) {
            if (!_form.currentState!.validate()) return;
            _selected = parseDateInput(_text.text)!;
          }
          Navigator.pop(context, _selected);
        },
        child: const Text('Seç'),
      ),
    ],
  );
}
