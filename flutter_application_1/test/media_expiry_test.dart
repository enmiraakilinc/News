import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/media/chat_media.dart';

void main() {
  test(
    'existing attachments keep two days, extensions apply to all media kinds',
    () {
      final created = DateTime.utc(2026, 10, 24);
      for (final kind in ['photo', 'video', 'audio', 'file']) {
        final data = <String, dynamic>{
          'kind': kind,
          'createdAt': Timestamp.fromDate(created),
        };
        expect(
          chatMediaExpiresAt(data).toUtc(),
          created.add(const Duration(days: 2)),
        );
        final until = created.add(const Duration(days: 7));
        data['expiresAt'] = Timestamp.fromDate(until);
        expect(chatMediaExpiresAt(data).toUtc(), until);
        expect(
          chatAttachmentExpired(
            kind,
            created,
            created.add(const Duration(days: 3)),
            expiresAt: until,
          ),
          false,
        );
        expect(
          chatAttachmentExpired(kind, created, until, expiresAt: until),
          true,
        );
      }
    },
  );
}
