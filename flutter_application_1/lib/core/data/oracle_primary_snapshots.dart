import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_codec.dart';
import 'oracle_primary_store.dart';

DocumentSnapshotPlatform oraclePrimaryDocument(
  FirebaseFirestorePlatform owner,
  OracleCodec codec,
  String path,
  OracleStoreSnapshot view,
) {
  final row = view.rows.where((r) => r['path'] == path).firstOrNull;
  return DocumentSnapshotPlatform(
    owner,
    path,
    row == null ? null : codec.fields(row['document']['fields'] as Map? ?? {}),
    InternalSnapshotMetadata(
      hasPendingWrites: view.pendingPaths.contains(path),
      isFromCache: view.fromCache,
    ),
  );
}

QuerySnapshotPlatform oraclePrimaryQuery(
  FirebaseFirestorePlatform owner,
  OracleCodec codec,
  OracleStoreSnapshot view, [
  List<Map<String, dynamic>> previous = const [],
]) {
  final docs = [
    for (final row in view.rows)
      DocumentSnapshotPlatform(
        owner,
        row['path'] as String,
        codec.fields(row['document']['fields'] as Map? ?? {}),
        InternalSnapshotMetadata(
          hasPendingWrites: view.pendingPaths.contains(row['path']),
          isFromCache: view.fromCache,
        ),
      ),
  ];
  final changes = <DocumentChangePlatform>[];
  final working = [...previous];
  final present = view.rows.map((r) => r['path']).toSet();
  for (var i = working.length - 1; i >= 0; i--) {
    if (!present.contains(working[i]['path'])) {
      final old = working.removeAt(i);
      changes.add(
        DocumentChangePlatform(
          DocumentChangeType.removed,
          i,
          -1,
          oraclePrimaryDocument(
            owner,
            codec,
            old['path'] as String,
            OracleStoreSnapshot([old], view.fromCache, view.pendingPaths),
          ),
        ),
      );
    }
  }
  for (var i = 0; i < view.rows.length; i++) {
    final row = view.rows[i],
        index = working.indexWhere((r) => r['path'] == row['path']);
    if (index < 0) {
      working.insert(i, row);
      changes.add(
        DocumentChangePlatform(DocumentChangeType.added, -1, i, docs[i]),
      );
    } else {
      final old = working[index];
      if (index != i || old['version'] != row['version']) {
        working.removeAt(index);
        working.insert(i, row);
        changes.add(
          DocumentChangePlatform(
            DocumentChangeType.modified,
            index,
            i,
            docs[i],
          ),
        );
      }
    }
  }
  return QuerySnapshotPlatform(
    docs,
    changes,
    SnapshotMetadataPlatform(view.pendingPaths.isNotEmpty, view.fromCache),
  );
}
