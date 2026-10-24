import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_firestore_bridge.dart';

/// Small direct-VPS facade. It deliberately has no Firebase SDK data delegate.
class DirectPersonalDb {
  final String owner;
  final OracleFirestoreBridge? connection;
  DirectPersonalDb(this.owner, {this.connection});
  OracleFirestoreBridge get bridge {
    final value = connection ?? FirebaseFirestorePlatform.instance;
    if (value is! OracleFirestoreBridge ||
        !value.primary ||
        value.store.uid != owner) {
      throw StateError('Kişisel sunucu bağlantısı hazır değil. Tekrar aç.');
    }
    return value;
  }

  void guard() {
    bridge;
  }

  DirectPersonalRef doc(String path) => DirectPersonalRef(this, path);
  DirectPersonalBatch batch() => DirectPersonalBatch(this);
  Future<T> runTransaction<T>(
    Future<T> Function(DirectPersonalTransaction) work,
  ) async {
    final result = await bridge.runTransaction<T>(
      (tx) => work(DirectPersonalTransaction(this, tx)),
    );
    return result as T;
  }
}

class DirectPersonalSnapshot {
  final String id;
  final Map<String, dynamic>? _data;
  DirectPersonalSnapshot(this.id, this._data);
  bool get exists => _data != null;
  Map<String, dynamic>? data() => _data;
}

class DirectPersonalQueryResult {
  final List<DirectPersonalSnapshot> docs;
  DirectPersonalQueryResult(this.docs);
}

class DirectPersonalRef {
  final DirectPersonalDb db;
  final String path;
  DirectPersonalRef(this.db, this.path);
  String get id => path.split('/').last;
  DirectPersonalCollection collection(String name) =>
      DirectPersonalCollection(db, '$path/$name');
  Future<DirectPersonalSnapshot> get([
    GetOptions options = const GetOptions(),
  ]) async {
    final bridge = db.bridge,
        view = await bridge.store.get(
          {'kind': 'document', 'path': path},
          cacheOnly: options.source == Source.cache,
          serverOnly: options.source == Source.server,
        );
    db.guard();
    return DirectPersonalSnapshot(
      id,
      view.rows.isEmpty
          ? null
          : bridge.codec.fields(view.rows.single['document']['fields'] as Map),
    );
  }

  Future<void> set(Map<String, dynamic> data) async {
    final bridge = db.bridge;
    await bridge.store.outbox.enqueue([bridge.writes.set(path, data)]);
    db.guard();
  }

  Future<void> update(Map<String, dynamic> data) async {
    final bridge = db.bridge;
    await bridge.store.outbox.enqueue([
      bridge.writes.update(path, {
        for (final entry in data.entries)
          FieldPath(entry.key.split('.')): entry.value,
      }),
    ]);
    db.guard();
  }
}

class DirectPersonalCollection {
  final DirectPersonalDb db;
  final String path;
  final List<Map<String, dynamic>> filters;
  DirectPersonalCollection(this.db, this.path, [this.filters = const []]);
  DirectPersonalRef doc(String id) => DirectPersonalRef(db, '$path/$id');
  DirectPersonalCollection where(String field, {required dynamic isEqualTo}) =>
      DirectPersonalCollection(db, path, [
        ...filters,
        {
          'field': field.split('.'),
          'op': '==',
          'value': db.bridge.codec.encode(isEqualTo),
        },
      ]);
  Future<DirectPersonalQueryResult> get() async {
    final bridge = db.bridge,
        view = await bridge.store.get({
          'kind': 'query',
          'query': {'path': path, 'filters': filters},
        });
    db.guard();
    return DirectPersonalQueryResult([
      for (final row in view.rows)
        DirectPersonalSnapshot(
          (row['path'] as String).split('/').last,
          bridge.codec.fields(row['document']['fields'] as Map),
        ),
    ]);
  }
}

class DirectPersonalBatch {
  final DirectPersonalDb db;
  final _operations = <Map<String, dynamic>>[];
  DirectPersonalBatch(this.db);
  void set(DirectPersonalRef reference, Map<String, dynamic> data) =>
      _operations.add(db.bridge.writes.set(reference.path, data));
  void delete(DirectPersonalRef reference) =>
      _operations.add({'type': 'delete', 'path': reference.path});
  Future<void> commit() async {
    if (_operations.isNotEmpty) {
      await db.bridge.store.outbox.enqueue(_operations);
    }
    db.guard();
  }
}

class DirectPersonalTransaction {
  final DirectPersonalDb db;
  final TransactionPlatform transaction;
  DirectPersonalTransaction(this.db, this.transaction);
  Future<DirectPersonalSnapshot> get(DirectPersonalRef reference) async {
    db.guard();
    final value = await transaction.get(reference.path);
    db.guard();
    return DirectPersonalSnapshot(reference.id, value.data());
  }

  void set(DirectPersonalRef reference, Map<String, dynamic> data) {
    db.guard();
    transaction.set(reference.path, data);
  }
}
