const List<String> turkishMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Depolama için: 2026-03-17
String formatIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Ekranda göstermek için: 17 Mart 2026
String formatDisplayDate(DateTime date) =>
    '${date.day} ${turkishMonths[date.month - 1]} ${date.year}';

/// Saat: 14:32
String formatClock(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// Tarih ve saat: 5 Mart 2026, 14:32
String formatDisplayDateTime(DateTime date) =>
    '${formatDisplayDate(date)}, ${formatClock(date)}';
