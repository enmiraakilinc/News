import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_codec.dart';
import 'oracle_primary_store.dart';
import 'oracle_primary_snapshots.dart';
import 'oracle_write_codec.dart';

class OraclePrimaryTransaction extends TransactionPlatform {
  final OraclePrimaryStore store;
  final FirebaseFirestorePlatform owner;
  final OracleCodec codec;
  final OracleWriteCodec writes;
  final bool Function() isActive;
  final operations = <Map<String, dynamic>>[];
  final conditions = <String, String?>{};
  OraclePrimaryTransaction(
    this.store,
    this.owner,
    this.codec, {
    bool Function()? isActive,
  }) : isActive = isActive ?? (() => true),
       writes = OracleWriteCodec(codec);
  @override
  List<InternalTransactionCommand> get commands => const [];
  @override
  Future<DocumentSnapshotPlatform> get(String documentPath) async {
    if (!isActive()) throw StateError('İşlem süresi doldu.');
    if (operations.isNotEmpty) {
      throw StateError('İşlemde okumalar yazmalardan önce olmalı.');
    }
    final view = await store.get(
      {'kind': 'document', 'path': documentPath},
      serverOnly: true,
      includePending: false,
    );
    conditions[documentPath] = view.rows.firstOrNull?['version']?.toString();
    return oraclePrimaryDocument(owner, codec, documentPath, view);
  }

  @override
  TransactionPlatform set(
    String documentPath,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    operations.add(writes.set(documentPath, data, options));
    return this;
  }

  @override
  TransactionPlatform update(
    String documentPath,
    Map<FieldPath, dynamic> data,
  ) {
    operations.add(writes.update(documentPath, data));
    return this;
  }

  @override
  TransactionPlatform delete(String documentPath) {
    operations.add({'type': 'delete', 'path': documentPath});
    return this;
  }

  Future<void> commit() async {
    if (operations.isEmpty) return;
    final response = await store.outbox.transaction(operations, [
      for (final entry in conditions.entries)
        {'path': entry.key, 'version': entry.value},
    ], isActive: isActive);
    store.acceptCommit(operations, response);
    store.notifyCommitted();
  }
}
