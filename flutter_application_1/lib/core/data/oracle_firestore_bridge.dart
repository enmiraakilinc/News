import 'dart:async';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'oracle_client.dart';
import 'oracle_codec.dart';

/// Staged rollout: native listeners, offline queues, transactions and Android
/// call/wake services stay intact while one-shot reads prefer PostgreSQL.
void installOracleReadBridge() {
  const enabled = bool.fromEnvironment('NEURAL_POSTGRES_READS');
  if (!enabled || FirebaseFirestorePlatform.instance is OracleFirestoreBridge) {
    return;
  }
  FirebaseFirestorePlatform.instance = OracleFirestoreBridge(
    FirebaseFirestorePlatform.instance,
    OracleDataClient(
      token: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    ),
  );
}

class OracleFirestoreBridge extends FirebaseFirestorePlatform {
  final FirebaseFirestorePlatform native;
  final OracleDataClient client;
  @override
  FirebaseApp get app => native.app;
  @override
  String get databaseId => native.databaseId;
  int _pending = 0;
  bool _networkDisabled = false;
  DateTime _nativeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  OracleFirestoreBridge(this.native, this.client);
  bool get preferNative =>
      _networkDisabled || _pending > 0 || DateTime.now().isBefore(_nativeUntil);
  Future<T> mutate<T>(Future<T> Function() work) async {
    _pending++;
    try {
      return await work();
    } finally {
      _pending--;
      _nativeUntil = DateTime.now().add(const Duration(seconds: 5));
    }
  }

  late final codec = OracleCodec(
    reference: doc,
    project: native.app.options.projectId,
  );
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) {
    // Platform factory API; preserving the original delegate is intentional.
    // ignore: invalid_use_of_protected_member
    return OracleFirestoreBridge(
      native.delegateFor(app: app, databaseId: databaseId),
      client,
    );
  }

  DocumentSnapshotPlatform snapshot(String path, Map? row) =>
      DocumentSnapshotPlatform(
        this,
        path,
        row == null
            ? null
            : codec.fields(row['document']['fields'] as Map? ?? {}),
        InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
      );
  DocumentSnapshotPlatform rebindDoc(DocumentSnapshotPlatform value) =>
      DocumentSnapshotPlatform(
        this,
        value.reference.path,
        value.data(),
        InternalSnapshotMetadata(
          hasPendingWrites: value.metadata.hasPendingWrites,
          isFromCache: value.metadata.isFromCache,
        ),
      );
  QuerySnapshotPlatform rebindQuery(QuerySnapshotPlatform value) =>
      QuerySnapshotPlatform(value.docs.map(rebindDoc).toList(), [
        for (final c in value.docChanges)
          DocumentChangePlatform(
            c.type,
            c.oldIndex,
            c.newIndex,
            rebindDoc(c.document),
          ),
      ], value.metadata);
  @override
  DocumentReferencePlatform doc(String documentPath) =>
      _OracleDocument(this, native.doc(documentPath));
  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      _OracleCollection(this, native.collection(collectionPath));
  @override
  QueryPlatform collectionGroup(String collectionPath) =>
      native.collectionGroup(collectionPath);
  @override
  WriteBatchPlatform batch() => _OracleBatch(this, native.batch());
  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) => mutate(
    () => native.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    ),
  );
  @override
  Settings get settings => native.settings;
  @override
  set settings(Settings value) => native.settings = value;
  @override
  Future<void> clearPersistence() => native.clearPersistence();
  @override
  Future<void> disableNetwork() async {
    _networkDisabled = true;
    await native.disableNetwork();
  }

  @override
  Future<void> enableNetwork() async {
    await native.enableNetwork();
    _networkDisabled = false;
  }

  @override
  Future<void> terminate() => native.terminate();
  @override
  Future<void> waitForPendingWrites() => native.waitForPendingWrites();
  @override
  Stream<void> snapshotsInSync() => native.snapshotsInSync();
  @override
  Future<void> setLoggingEnabled(bool enabled) =>
      native.setLoggingEnabled(enabled);
}

class _OracleDocument extends DocumentReferencePlatform {
  final OracleFirestoreBridge bridge;
  final DocumentReferencePlatform native;
  _OracleDocument(this.bridge, this.native) : super(bridge, native.path);
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    if (options.source == Source.cache || bridge.preferNative) {
      return bridge.rebindDoc(await native.get(options));
    }
    try {
      final result = await bridge.client.read({
        'kind': 'document',
        'path': path,
      });
      // A just-created invite/membership may not be mirrored yet.
      if (result['row'] == null) {
        return bridge.rebindDoc(await native.get(options));
      }
      return bridge.snapshot(path, result['row'] as Map);
    } catch (e) {
      if (!oracleShouldFallback(e)) rethrow;
      return bridge.rebindDoc(await native.get(options));
    }
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => native
      .snapshots(
        includeMetadataChanges: includeMetadataChanges,
        listenSource: listenSource,
      )
      .map(bridge.rebindDoc);
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      bridge.mutate(() => native.set(data, options));
  @override
  Future<void> update(Map<FieldPath, dynamic> data) =>
      bridge.mutate(() => native.update(data));
  @override
  Future<void> delete() => bridge.mutate(native.delete);
}

mixin _OracleQueryReads on QueryPlatform {
  OracleFirestoreBridge get bridge;
  QueryPlatform get native;
  String get queryPath;
  _OracleQuery wrap(QueryPlatform query) =>
      _OracleQuery(bridge, query, queryPath);
  List<String> _field(dynamic value) {
    if (value == FieldPath.documentId) return ['__name__'];
    if (value is FieldPath) return value.components;
    if (value is String) return value.split('.');
    throw UnsupportedError('Desteklenmeyen alan.');
  }

  Map<String, dynamic> request() {
    if (native.parameters['filters'] != null) {
      throw UnsupportedError('Bileşik filtre.');
    }
    final orders = [
      for (final o in (native.parameters['orderBy'] as Iterable? ?? []))
        {'field': _field(o[0]), 'descending': o[1]},
    ];
    Map<String, dynamic> encode(dynamic value, List<String> field) {
      if (field.length == 1 &&
          field.first == '__name__' &&
          value is String &&
          !value.contains('/')) {
        value = '$queryPath/$value';
      }
      return bridge.codec.encode(value);
    }

    return {
      'path': queryPath,
      'filters': [
        for (final f in (native.parameters['where'] as Iterable? ?? []))
          {
            'field': _field(f[0]),
            'op': f[1],
            'value': encode(f[2], _field(f[0])),
          },
      ],
      'orders': orders,
      if (native.parameters['limit'] != null)
        'limit': native.parameters['limit'],
      if (native.parameters['limitToLast'] != null) ...{
        'limit': native.parameters['limitToLast'],
        'limitToLast': true,
      },
      for (final key in ['startAt', 'startAfter', 'endAt', 'endBefore'])
        if (native.parameters[key] != null)
          key: [
            for (final (i, value)
                in (native.parameters[key] as Iterable).indexed)
              encode(
                value,
                i < orders.length
                    ? orders[i]['field'] as List<String>
                    : ['__name__'],
              ),
          ],
    };
  }

  @override
  bool get isCollectionGroupQuery => false;
  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    if (options.source == Source.cache || bridge.preferNative) {
      return bridge.rebindQuery(await native.get(options));
    }
    try {
      final result = await bridge.client.read({
        'kind': 'query',
        'query': request(),
      });
      final rows = result['rows'] as List;
      // Native writes remain authoritative during the compatibility rollout.
      if (rows.isEmpty) return bridge.rebindQuery(await native.get(options));
      final docs = [
        for (final row in rows)
          bridge.snapshot(row['path'] as String, row as Map),
      ];
      return QuerySnapshotPlatform(docs, [
        for (final (i, doc) in docs.indexed)
          DocumentChangePlatform(DocumentChangeType.added, -1, i, doc),
      ], SnapshotMetadataPlatform(false, false));
    } catch (e) {
      if (!oracleShouldFallback(e)) rethrow;
      return bridge.rebindQuery(await native.get(options));
    }
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => native
      .snapshots(
        includeMetadataChanges: includeMetadataChanges,
        listenSource: listenSource,
      )
      .map(bridge.rebindQuery);
  @override
  QueryPlatform where(List<List<dynamic>> conditions) =>
      wrap(native.where(conditions));
  @override
  QueryPlatform whereFilter(FilterPlatformInterface filter) =>
      wrap(native.whereFilter(filter));
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      wrap(native.orderBy(orders));
  @override
  QueryPlatform limit(int limit) => wrap(native.limit(limit));
  @override
  QueryPlatform limitToLast(int limit) => wrap(native.limitToLast(limit));
  @override
  QueryPlatform startAfterDocument(
    List<dynamic> orders,
    List<dynamic> values,
  ) => wrap(native.startAfterDocument(orders, values));
  @override
  QueryPlatform startAtDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) => wrap(native.startAtDocument(orders, values));
  @override
  QueryPlatform endAtDocument(List<dynamic> orders, List<dynamic> values) =>
      wrap(native.endAtDocument(orders, values));
  @override
  QueryPlatform endBeforeDocument(
    Iterable<dynamic> orders,
    Iterable<dynamic> values,
  ) => wrap(native.endBeforeDocument(orders, values));
  @override
  QueryPlatform startAt(Iterable<dynamic> values) =>
      wrap(native.startAt(values));
  @override
  QueryPlatform startAfter(Iterable<dynamic> values) =>
      wrap(native.startAfter(values));
  @override
  QueryPlatform endAt(Iterable<dynamic> values) => wrap(native.endAt(values));
  @override
  QueryPlatform endBefore(Iterable<dynamic> values) =>
      wrap(native.endBefore(values));
  @override
  AggregateQueryPlatform count() => _OracleCount(this, bridge);
}

class _OracleQuery extends QueryPlatform with _OracleQueryReads {
  @override
  final OracleFirestoreBridge bridge;
  @override
  final QueryPlatform native;
  @override
  final String queryPath;
  _OracleQuery(this.bridge, this.native, this.queryPath)
    : super(bridge, native.parameters);
}

class _OracleCollection extends CollectionReferencePlatform
    with _OracleQueryReads {
  @override
  final OracleFirestoreBridge bridge;
  @override
  final CollectionReferencePlatform native;
  @override
  Map<String, dynamic> get parameters => native.parameters;
  @override
  String get queryPath => path;
  _OracleCollection(this.bridge, this.native) : super(bridge, native.path);
  @override
  DocumentReferencePlatform doc([String? path]) =>
      _OracleDocument(bridge, native.doc(path));
}

class _OracleCount extends AggregateQueryPlatform {
  final _OracleQueryReads sourceQuery;
  final OracleFirestoreBridge bridge;
  _OracleCount(this.sourceQuery, this.bridge) : super(sourceQuery);
  @override
  Future<AggregateQuerySnapshotPlatform> get({
    required AggregateSource source,
  }) async {
    if (bridge.preferNative) {
      return sourceQuery.native.count().get(source: source);
    }
    try {
      final result = await bridge.client.read({
        'kind': 'count',
        'query': sourceQuery.request(),
      });
      return AggregateQuerySnapshotPlatform(
        count: result['count'] as int,
        sum: [],
        average: [],
      );
    } catch (e) {
      if (!oracleShouldFallback(e)) rethrow;
      return sourceQuery.native.count().get(source: source);
    }
  }
}

class _OracleBatch extends WriteBatchPlatform {
  final OracleFirestoreBridge bridge;
  final WriteBatchPlatform native;
  _OracleBatch(this.bridge, this.native);
  @override
  void set(String path, Map<String, dynamic> data, [SetOptions? options]) =>
      native.set(path, data, options);
  @override
  void update(String path, Map<FieldPath, dynamic> data) =>
      native.update(path, data);
  @override
  void delete(String path) => native.delete(path);
  @override
  Future<void> commit() => bridge.mutate(native.commit);
}
