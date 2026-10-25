String? chatDeliveryStatus({
  required bool pending,
  required bool mine,
  required bool edited,
  required bool read,
}) {
  if (pending) return 'Gönderiliyor…';
  if (!mine) return edited ? 'düzenlendi' : null;
  return '${read ? '✓✓ Okundu' : '✓ İletildi'}${edited ? ' · düzenlendi' : ''}';
}
