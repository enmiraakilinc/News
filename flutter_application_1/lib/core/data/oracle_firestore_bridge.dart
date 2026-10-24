import 'dart:io';
import 'oracle_primary_store.dart';
import 'oracle_primary_transport.dart';
import 'oracle_primary_snapshots.dart';
import 'oracle_primary_transaction.dart';
import 'oracle_write_codec.dart';
import 'dart:async';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'oracle_client.dart';
import 'oracle_codec.dart';

/// The compatibility build prefers mirrored reads. A primary build routes
/// documents, live queries, writes and transactions to the authenticated VPS.
void installOracleReadBridge() {
  const primary = bool.fromEnvironment('NEURAL_POSTGRES_PRIMARY');
  const enabled = bool.fromEnvironment('NEURAL_POSTGRES_READS') || primary;
  if (!enabled || FirebaseFirestorePlatform.instance is OracleFirestoreBridge) {
    return;
  }
  final bridge = OracleFirestoreBridge(
    FirebaseFirestorePlatform.instance,
    OracleDataClient(
      token: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    ),
    primary: primary,
  );
  FirebaseFirestorePlatform.instance = bridge;
  if (primary) {
    bridge.bindAccounts(
      FirebaseAuth.instance.authStateChanges().map((u) => u?.uid),
    );
  }
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
  final bool primary;
  final String? Function() _uidProvider;
  final OraclePrimaryTransport? _providedTransport;
  final Future<Directory> Function()? rootDirectory;
  final Map<String, OraclePrimaryStore> _stores;
  StreamSubscription<String?>? _accounts;
  OracleFirestoreBridge(
    this.native,
    this.client, {
    this.primary = false,
    String? Function()? uidProvider,
    OraclePrimaryTransport? transport,
    this.rootDirectory,
    Map<String, OraclePrimaryStore>? sharedStores,
  }) : _uidProvider =
           uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _providedTransport = transport,
       _stores = sharedStores ?? {};
  late final primaryTransport =
      _providedTransport ?? OraclePrimaryTransport(client);
  late final writes = OracleWriteCodec(codec);
  OraclePrimaryStore get store {
    final uid = _uidProvider();
    if (uid == null) throw OracleApiException(401, 'unauthenticated');
    return _stores.putIfAbsent(uid, () {
      final value = OraclePrimaryStore(
        uid: uid,
        isCurrent: () => _uidProvider() == uid,
        codec: codec,
        transport: primaryTransport,
        rootDirectory: rootDirectory,
      );
      value.networkEnabled = !_networkDisabled;
      value.outbox.enabled = !_networkDisabled;
      return value;
    });
  }

  void bindAccounts(Stream<String?> accounts) {
    unawaited(_accounts?.cancel());
    _accounts = accounts.listen((uid) {
      if (uid != _uidProvider()) return;
      for (final entry in _stores.entries.toList()) {
        if (entry.key != uid) {
          _stores.remove(entry.key);
          unawaited(
            entry.value.close().catchError((Object error, StackTrace stack) {
              /* Optional old cache cleanup. */
            }),
          );
        }
      }
    });
  }

  bool get preferNative =>
      _networkDisabled ||
      !primary && (_pending > 0 || DateTime.now().isBefore(_nativeUntil));
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
      primary: primary,
      uidProvider: _uidProvider,
      transport: primary ? primaryTransport : null,
      rootDirectory: rootDirectory,
      sharedStores: _stores,
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
  QueryPlatform collectionGroup(String collectionPath) {
    if (primary) throw UnsupportedError('Bu liste türü desteklenmiyor.');
    return native.collectionGroup(collectionPath);
  }

  @override
  WriteBatchPlatform batch() => _OracleBatch(this, native.batch());
  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (!primary) {
      return mutate(
        () => native.runTransaction(
          transactionHandler,
          timeout: timeout,
          maxAttempts: maxAttempts,
        ),
      );
    }
    var active = true;
    Future<T?> execute() async {
      final current = store;
      await current.outbox.waitForPendingWrites();
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!active) throw TimeoutException('İşlem zamanında tamamlanamadı.');
        final transaction = OraclePrimaryTransaction(
          current,
          this,
          codec,
          isActive: () => active,
        );
        try {
          final result = await transactionHandler(transaction);
          if (!active) throw TimeoutException('İşlem zamanında tamamlanamadı.');
          await transaction.commit();
          return result;
        } catch (error) {
          if (error is! OracleApiException ||
              error.code != 'aborted' ||
              attempt + 1 >= maxAttempts) {
            rethrow;
          }
        }
      }
      throw OracleApiException(409, 'aborted');
    }

    return execute()
        .timeout(
          timeout,
          onTimeout: () {
            active = false;
            throw TimeoutException('İşlem zamanında tamamlanamadı.');
          },
        )
        .whenComplete(() => active = false);
  }

  @override
  Settings get settings => native.settings;
  @override
  set settings(Settings value) => native.settings = value;
  @override
  Future<void> clearPersistence() async {
    if (!primary) {
      await native.clearPersistence();
      return;
    }
    for (final value in _stores.values) {
      await value.clearCache();
    }
  }

  @override
  Future<void> disableNetwork() async {
    _networkDisabled = true;
    if (primary) {
      for (final value in _stores.values) {
        await value.setNetwork(false);
      }
    } else {
      await native.disableNetwork();
    }
  }

  @override
  Future<void> enableNetwork() async {
    _networkDisabled = false;
    if (primary) {
      for (final value in _stores.values) {
        await value.setNetwork(true);
      }
    } else {
      await native.enableNetwork();
    }
  }

  @override
  Future<void> terminate() async {
    if (!primary) {
      await native.terminate();
      return;
    }
    await _accounts?.cancel();
    for (final value in _stores.values.toList()) {
      await value.close();
    }
    _stores.clear();
    primaryTransport.close();
  }

  @override
  Future<void> waitForPendingWrites() => primary
      ? store.outbox.waitForPendingWrites()
      : native.waitForPendingWrites();
  @override
  Stream<void> snapshotsInSync() =>
      primary ? store.changes : native.snapshotsInSync();
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
    if (bridge.primary) {
      final view = await bridge.store.get(
        {'kind': 'document', 'path': path},
        cacheOnly: options.source == Source.cache,
        serverOnly: options.source == Source.server,
      );
      return oraclePrimaryDocument(bridge, bridge.codec, path, view);
    }
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
  }) {
    if (bridge.primary) {
      return bridge.store
          .watch({
            'kind': 'document',
            'path': path,
          }, cacheOnly: listenSource == ListenSource.cache)
          .map(
            (view) => oraclePrimaryDocument(bridge, bridge.codec, path, view),
          );
    }
    return native
        .snapshots(
          includeMetadataChanges: includeMetadataChanges,
          listenSource: listenSource,
        )
        .map(bridge.rebindDoc);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (bridge.primary) {
      await bridge.store.outbox.enqueue([
        bridge.writes.set(path, data, options),
      ]);
      return;
    }
    await bridge.mutate(() => native.set(data, options));
  }

  @override
  Future<void> update(Map<FieldPath, dynamic> data) async {
    if (bridge.primary) {
      await bridge.store.outbox.enqueue([bridge.writes.update(path, data)]);
      return;
    }
    await bridge.mutate(() => native.update(data));
  }

  @override
  Future<void> delete() async {
    if (bridge.primary) {
      await bridge.store.outbox.enqueue([
        {'type': 'delete', 'path': path},
      ]);
      return;
    }
    await bridge.mutate(native.delete);
  }
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
    if (bridge.primary) {
      final view = await bridge.store.get(
        {'kind': 'query', 'query': request()},
        cacheOnly: options.source == Source.cache,
        serverOnly: options.source == Source.server,
      );
      return oraclePrimaryQuery(bridge, bridge.codec, view);
    }
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
  }) {
    if (bridge.primary) {
      var previous = <Map<String, dynamic>>[];
      return bridge.store
          .watch({
            'kind': 'query',
            'query': request(),
          }, cacheOnly: listenSource == ListenSource.cache)
          .map((view) {
            final snapshot = oraclePrimaryQuery(
              bridge,
              bridge.codec,
              view,
              previous,
            );
            previous = view.rows;
            return snapshot;
          });
    }
    return native
        .snapshots(
          includeMetadataChanges: includeMetadataChanges,
          listenSource: listenSource,
        )
        .map(bridge.rebindQuery);
  }

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
    if (bridge.primary) {
      if (bridge._networkDisabled) throw OracleApiException(503, 'unavailable');
      final count = await bridge.store.count(sourceQuery.request());
      return AggregateQuerySnapshotPlatform(count: count, sum: [], average: []);
    }
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
  final _operations = <Map<String, dynamic>>[];
  bool _committed = false;
  _OracleBatch(this.bridge, this.native);
  void _check() {
    if (_committed) throw StateError('Bu işlem grubu zaten gönderildi.');
  }

  @override
  void set(String path, Map<String, dynamic> data, [SetOptions? options]) {
    if (!bridge.primary) {
      native.set(path, data, options);
      return;
    }
    _check();
    _operations.add(bridge.writes.set(path, data, options));
  }

  @override
  void update(String path, Map<FieldPath, dynamic> data) {
    if (!bridge.primary) {
      native.update(path, data);
      return;
    }
    _check();
    _operations.add(bridge.writes.update(path, data));
  }

  @override
  void delete(String path) {
    if (!bridge.primary) {
      native.delete(path);
      return;
    }
    _check();
    _operations.add({'type': 'delete', 'path': path});
  }

  @override
  Future<void> commit() async {
    if (!bridge.primary) {
      await bridge.mutate(native.commit);
      return;
    }
    _check();
    _committed = true;
    if (_operations.isNotEmpty) await bridge.store.outbox.enqueue(_operations);
  }
}
