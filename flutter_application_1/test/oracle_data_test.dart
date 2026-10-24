import 'dart:io';
import 'package:flutter_application_1/core/data/oracle_personal_store.dart';
import 'package:flutter_application_1/core/data/personal_cloud.dart';
import 'package:flutter_application_1/core/data/oracle_local_values.dart';
import 'package:flutter_application_1/core/data/oracle_primary_transport.dart';
import 'package:flutter_application_1/core/data/oracle_write_codec.dart';
import 'package:flutter_application_1/core/data/oracle_media_batch.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as sdk;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/core/data/oracle_client.dart';
import 'package:flutter_application_1/core/data/oracle_codec.dart';
import 'package:flutter_application_1/core/data/oracle_firestore_bridge.dart';

Future<void> _removeTestDirectory(Directory directory) async {
  final resolved = await directory.resolveSymbolicLinks(),
      root = await Directory.systemTemp.resolveSymbolicLinks();
  expect(resolved.startsWith(root + Platform.pathSeparator), true);
  expect(
    directory.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last
        .startsWith('neural_'),
    true,
  );
  await directory.delete(recursive: true);
}

class _App implements FirebaseApp {
  @override
  String get name => '[DEFAULT]';
  @override
  FirebaseOptions get options => const FirebaseOptions(
    apiKey: 'test',
    appId: 'test',
    messagingSenderId: 'test',
    projectId: 'star-galeri',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Native extends FirebaseFirestorePlatform {
  int gets = 0, sets = 0, batches = 0;
  Completer<void>? gate;
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  Future<void> disableNetwork() async {}
  @override
  Future<void> enableNetwork() async {}
  @override
  FirebaseApp get app => _App();
  @override
  DocumentReferencePlatform doc(String documentPath) =>
      _Doc(this, documentPath);
  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      _Collection(this, collectionPath);
  @override
  WriteBatchPlatform batch() => _Batch(this);
}

DocumentSnapshotPlatform _nativeSnapshot(
  FirebaseFirestorePlatform db,
  String path,
) => DocumentSnapshotPlatform(db, path, {
  'value': 'native',
}, InternalSnapshotMetadata(hasPendingWrites: true, isFromCache: true));

class _Doc extends DocumentReferencePlatform {
  final _Native db;
  _Doc(this.db, String path) : super(db, path);
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    db.gets++;
    return _nativeSnapshot(db, path);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.sets++;
    await db.gate?.future;
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => Stream.value(_nativeSnapshot(db, path));
}

class _Collection extends CollectionReferencePlatform {
  final _Native db;
  _Collection(this.db, String path) : super(db, path);
  @override
  Map<String, dynamic> get parameters => {
    'where': <List<dynamic>>[],
    'orderBy': <List<dynamic>>[],
    'startAt': null,
    'startAfter': null,
    'endAt': null,
    'endBefore': null,
    'limit': null,
    'limitToLast': null,
  };
  @override
  QueryPlatform where(List<List<dynamic>> conditions) =>
      _Query(db, path, {...parameters, 'where': conditions});
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) =>
      _Query(db, path, {...parameters, 'orderBy': orders});

  @override
  DocumentReferencePlatform doc([String? path]) =>
      db.doc('${this.path}/${path ?? 'generated'}');
  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    db.gets++;
    return QuerySnapshotPlatform(
      [_nativeSnapshot(db, '$path/a')],
      [],
      SnapshotMetadataPlatform(true, true),
    );
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => Stream.value(
    QuerySnapshotPlatform(
      [_nativeSnapshot(db, '$path/a')],
      [],
      SnapshotMetadataPlatform(true, true),
    ),
  );
}

class _Query extends QueryPlatform {
  final _Native db;
  final String path;
  _Query(this.db, this.path, Map<String, dynamic> params) : super(db, params);
  @override
  bool get isCollectionGroupQuery => false;
  _Query copy(Map<String, dynamic> values) =>
      _Query(db, path, {...parameters, ...values});
  @override
  QueryPlatform where(List<List<dynamic>> values) => copy({'where': values});
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> values) =>
      copy({'orderBy': values});
  @override
  QueryPlatform limit(int value) => copy({'limit': value});
  @override
  QueryPlatform startAfterDocument(
    List<dynamic> orders,
    List<dynamic> values,
  ) => copy({'orderBy': orders, 'startAfter': values});
}

class _Batch extends WriteBatchPlatform {
  final _Native db;
  _Batch(this.db);
  @override
  Future<void> commit() async {
    db.batches++;
  }
}

http.Response _documentResponse() => http.Response(
  jsonEncode({
    'row': {
      'path': 'chats/a',
      'document': {
        'fields': {
          'value': {'stringValue': 'postgres'},
        },
      },
    },
  }),
  200,
);

void main() {
  final codec = OracleCodec(
    reference: (_) => throw UnimplementedError(),
    project: 'star-galeri',
  );
  test('binary payload and timestamp nanoseconds round trip unchanged', () {
    final bytes = Uint8List.fromList([0, 255, 10, 35]);
    expect((codec.decode(codec.encode(Blob(bytes))) as Blob).bytes, bytes);
    final timestamp = Timestamp(1790000000, 123456789);
    final restored = codec.decode(codec.encode(timestamp)) as Timestamp;
    expect(restored.seconds, timestamp.seconds);
    expect(restored.nanoseconds, timestamp.nanoseconds);
  });
  test('int64 and nested encrypted data round trip', () {
    final data = <String, dynamic>{
      'max': 9223372036854775807,
      'cipher': 'opaque+encrypted==',
      'nested': <String, dynamic>{
        'items': [null, true, 3],
      },
    };
    expect(codec.decode(codec.encode(data)), data);
  });
  test('timestamps without fractional seconds decode', () {
    final t =
        codec.decode({'timestampValue': '2026-10-24T10:00:00Z'}) as Timestamp;
    expect(t.nanoseconds, 0);
  });
  test('plaintext URLs are refused', () {
    expect(
      () => OracleDataClient(
        token: () async => null,
        base: Uri.parse('http://138.2.185.151'),
      ),
      throwsArgumentError,
    );
  });
  test(
    'bearer changes with the account and never appears in the URL',
    () async {
      var token = 'first';
      final seen = <String>[];
      final client = OracleDataClient(
        token: () async => token,
        client: MockClient((r) async {
          expect(r.url.query, isEmpty);
          expect(r.url.path, '/v1/read');
          seen.add(r.headers['Authorization']!);
          return _documentResponse();
        }),
      );
      await client.read({'kind': 'document', 'path': 'chats/a'});
      token = 'second';
      await client.read({'kind': 'document', 'path': 'chats/a'});
      expect(seen, ['Bearer first', 'Bearer second']);
      client.close();
    },
  );
  test(
    'one-shot read uses PostgreSQL and decodes SDK-compatible snapshots',
    () async {
      final native = _Native();
      final bridge = OracleFirestoreBridge(
        native,
        OracleDataClient(
          token: () async => 'test',
          client: MockClient((_) async => _documentResponse()),
        ),
      );
      final doc = await bridge.doc('chats/a').get();
      expect(doc.data()?['value'], 'postgres');
      expect(doc.reference.path, 'chats/a');
      expect(doc.metadata.hasPendingWrites, false);
      expect(native.gets, 0);
    },
  );
  test('cache-only reads do not make an API request', () async {
    final native = _Native();
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(
        token: () async => 'test',
        client: MockClient(
          (_) async => throw StateError('Network must not be called'),
        ),
      ),
    );
    final doc = await bridge
        .doc('chats/a')
        .get(const GetOptions(source: Source.cache));
    expect(doc.data()?['value'], 'native');
    expect(doc.metadata.hasPendingWrites, true);
  });
  test('server outage falls back to existing SDK', () async {
    final native = _Native();
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(
        token: () async => 'test',
        client: MockClient(
          (_) async => http.Response('{"error":{"code":"unavailable"}}', 503),
        ),
      ),
    );
    expect((await bridge.doc('chats/a').get()).data()?['value'], 'native');
    expect(native.gets, 1);
  });
  test(
    'permission denials do not fall through to another data source',
    () async {
      final native = _Native();
      final bridge = OracleFirestoreBridge(
        native,
        OracleDataClient(
          token: () async => 'test',
          client: MockClient(
            (_) async =>
                http.Response('{"error":{"code":"permission-denied"}}', 403),
          ),
        ),
      );
      await expectLater(
        bridge.doc('chats/a').get(),
        throwsA(isA<OracleApiException>()),
      );
      expect(native.gets, 0);
    },
  );
  test('missing mirrored rows are checked against authoritative SDK', () async {
    final native = _Native();
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(
        token: () async => 'test',
        client: MockClient((_) async => http.Response('{"row":null}', 200)),
      ),
    );
    expect((await bridge.doc('chats/a').get()).data()?['value'], 'native');
  });
  test(
    'native write and read-your-writes remain intact during replication',
    () async {
      final native = _Native()..gate = Completer<void>();
      final bridge = OracleFirestoreBridge(
        native,
        OracleDataClient(
          token: () async => 'test',
          client: MockClient(
            (_) async => throw StateError('Stale replica must not be read'),
          ),
        ),
      );
      final work = bridge.doc('chats/a').set({'value': 'new'});
      expect(bridge.preferNative, true);
      expect((await bridge.doc('chats/a').get()).data()?['value'], 'native');
      native.gate!.complete();
      await work;
      expect(native.sets, 1);
      expect(bridge.preferNative, true);
    },
  );
  test(
    'live snapshots preserve native cache and pending-write metadata',
    () async {
      final bridge = OracleFirestoreBridge(
        _Native(),
        OracleDataClient(
          token: () async => null,
          client: MockClient(
            (_) async => throw StateError('Live streams must remain native'),
          ),
        ),
      );
      final snapshot = await bridge
          .doc('chats/a')
          .snapshots(listenSource: ListenSource.defaultSource)
          .first;
      expect(snapshot.metadata.hasPendingWrites, true);
      expect(snapshot.metadata.isFromCache, true);
    },
  );
  test(
    'batch commit is delegated and activates read-your-writes protection',
    () async {
      final native = _Native();
      final bridge = OracleFirestoreBridge(
        native,
        OracleDataClient(token: () async => null),
      );
      await bridge.batch().commit();
      expect(native.batches, 1);
      expect(bridge.preferNative, true);
    },
  );
  test('query rows become SDK snapshots with stable reference paths', () async {
    final native = _Native();
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(
        token: () async => 'test',
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map;
          expect(body['query']['path'], 'couples/a/letters');
          return http.Response(
            jsonEncode({
              'rows': [
                {
                  'path': 'couples/a/letters/b',
                  'document': {
                    'fields': {
                      'cipher': {'stringValue': 'opaque'},
                    },
                  },
                },
              ],
            }),
            200,
          );
        }),
      ),
    );
    final result = await bridge.collection('couples/a/letters').get();
    expect(result.docs.single.reference.path, 'couples/a/letters/b');
    expect(result.docs.single.data()?['cipher'], 'opaque');
    expect(result.docChanges.single.type, DocumentChangeType.added);
    expect(native.gets, 0);
  });
  test(
    'outage circuit breaker prevents waiting once per media chunk',
    () async {
      var calls = 0;
      final client = OracleDataClient(
        token: () async => 'test',
        client: MockClient((_) async {
          calls++;
          return http.Response('{"error":{"code":"unavailable"}}', 503);
        }),
      );
      for (var i = 0; i < 3; i++) {
        await expectLater(
          client.read({'kind': 'document', 'path': 'chats/a'}),
          throwsA(isA<OracleApiException>()),
        );
      }
      expect(calls, 1);
      client.close();
    },
  );
  test('disableNetwork also prevents PostgreSQL network requests', () async {
    final native = _Native();
    var calls = 0;
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(
        token: () async => 'test',
        client: MockClient((_) async {
          calls++;
          return _documentResponse();
        }),
      ),
    );
    await bridge.disableNetwork();
    expect((await bridge.doc('chats/a').get()).data()?['value'], 'native');
    expect(calls, 0);
    await bridge.enableNetwork();
    expect((await bridge.doc('chats/a').get()).data()?['value'], 'postgres');
    expect(calls, 1);
  });
  test(
    'public SDK can build filtered ordered history and cursor queries',
    () async {
      var calls = 0;
      final native = _Native();
      final bridge = OracleFirestoreBridge(
        native,
        OracleDataClient(
          token: () async => 'test',
          client: MockClient((r) async {
            calls++;
            final q = (jsonDecode(r.body) as Map)['query'] as Map;
            expect(q['filters'][0]['field'], ['from']);
            expect(q['filters'][0]['value'], {'stringValue': 'owner'});
            expect(q['orders'][0]['field'], ['createdAt']);
            expect(q['limit'], 50);
            if (calls == 2) {
              expect(q['orders'][1]['field'], ['__name__']);
              expect(q['startAfter'][1], {
                'stringValue': 'couples/a/letters/b',
              });
            }
            return http.Response(
              jsonEncode({
                'rows': [
                  {
                    'path': 'couples/a/letters/b',
                    'document': {
                      'fields': {
                        'createdAt': {
                          'timestampValue': '2026-10-24T10:00:00.123456Z',
                        },
                        'from': {'stringValue': 'owner'},
                      },
                    },
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      FirebaseFirestorePlatform.instance = bridge;
      final db = sdk.FirebaseFirestore.instanceFor(app: _App());
      final query = db
          .collection('couples/a/letters')
          .where('from', isEqualTo: 'owner')
          .orderBy('createdAt', descending: true)
          .limit(50);
      final first = await query.get();
      expect(first.docs.single.data()['from'], 'owner');
      final second = await query.startAfterDocument(first.docs.single).get();
      expect(second.docs.single.id, 'b');
      expect(calls, 2);
      FirebaseFirestorePlatform.instance = native;
    },
  );
  test('references from native live snapshots keep write tracking', () async {
    final native = _Native();
    final bridge = OracleFirestoreBridge(
      native,
      OracleDataClient(token: () async => null),
    );
    final snapshot = await bridge
        .doc('chats/a')
        .snapshots(listenSource: ListenSource.defaultSource)
        .first;
    await snapshot.reference.set({'value': 'changed'});
    expect(native.sets, 1);
    expect(bridge.preferNative, true);
  });
  test(
    'Media batch preserves requested order, bytes and incomplete fallback',
    () async {
      final previous = FirebaseFirestorePlatform.instance;
      addTearDown(() => FirebaseFirestorePlatform.instance = previous);
      var complete = true;
      final client = OracleDataClient(
        token: () async => 'test',
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['kind'], 'documents');
          return http.Response(
            jsonEncode({
              'rows': [
                {
                  'path': 'chatMedia/a/chunks/1',
                  'document': {
                    'fields': {
                      'bytes': {'bytesValue': 'AgM='},
                    },
                  },
                },
                if (complete)
                  {
                    'path': 'chatMedia/a/chunks/0',
                    'document': {
                      'fields': {
                        'bytes': {'bytesValue': 'AQ=='},
                      },
                    },
                  },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      FirebaseFirestorePlatform.instance = OracleFirestoreBridge(
        _Native(),
        client,
      );
      final paths = ['chatMedia/a/chunks/0', 'chatMedia/a/chunks/1'];
      final parts = await readOracleMediaChunks(paths);
      expect((parts![0]['bytes'] as Blob).bytes, [1]);
      expect((parts[1]['bytes'] as Blob).bytes, [2, 3]);
      complete = false;
      expect(await readOracleMediaChunks(paths), isNull);
    },
  );
  test(
    'Primary write codec keeps SDK sentinels separate from ordinary maps',
    () {
      final codec = OracleWriteCodec(
        OracleCodec(reference: _Native().doc, project: 'star-galeri'),
      );
      expect(codec.encode(sdk.FieldValue.serverTimestamp()), {
        'transformValue': {'operation': 'serverTimestamp'},
      });
      expect(codec.encode(sdk.FieldValue.increment(2)), {
        'transformValue': {
          'operation': 'increment',
          'value': {'integerValue': '2'},
        },
      });
      expect(codec.encode(sdk.FieldValue.arrayUnion(['alice'])), {
        'transformValue': {
          'operation': 'arrayUnion',
          'value': {
            'arrayValue': {
              'values': [
                {'stringValue': 'alice'},
              ],
            },
          },
        },
      });
      expect(codec.encode(Uint8List.fromList([0, 255])), {
        'bytesValue': 'AP8=',
      });
      expect(
        codec
            .encode({
              'transformValue': {'operation': 'delete'},
            })
            .containsKey('mapValue'),
        true,
      );
      final op = codec.update('chats/a/messages/b', {
        FieldPath(['reactions', 'uid.with.dot']): 'heart',
      });
      expect((op['fields'] as List).single['field'], [
        'reactions',
        'uid.with.dot',
      ]);
      final set = codec.set(
        'couples/a/notes/b',
        {'a.b': 'text'},
        SetOptions(
          mergeFields: [
            FieldPath(['a.b']),
          ],
        ),
      );
      expect(set['mergeFields'], [
        ['a.b'],
      ]);
    },
  );

  test('Primary SDK never falls back to Firebase data operations', () async {
    final directory = await Directory.systemTemp.createTemp('neural_bridge_');
    addTearDown(() => _removeTestDirectory(directory));
    final native = _Native();
    var unavailable = false;
    var commits = 0;
    final mock = MockClient((request) async {
      if (unavailable) {
        return http.Response('{"error":{"code":"unavailable"}}', 503);
      }
      if (request.url.path.endsWith('/commit')) {
        commits++;
        return http.Response(
          jsonEncode({
            'requestId': (jsonDecode(request.body) as Map)['requestId'],
            'versions': {'chatProfiles/owner': '3'},
            'commitTime': '2026-10-24T18:00:00.000000000Z',
            'documents': [],
          }),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map;
      if (body['kind'] == 'count') return http.Response('{"count":7}', 200);
      return http.Response(
        jsonEncode({
          'row': {
            'path': 'chatProfiles/owner',
            'version': '1',
            'document': {
              'fields': {
                'value': {'stringValue': 'postgres'},
              },
            },
          },
        }),
        200,
      );
    });
    final api = OracleDataClient(token: () async => 'token', client: mock);
    final bridge = OracleFirestoreBridge(
      native,
      api,
      primary: true,
      uidProvider: () => 'owner',
      rootDirectory: () async => directory,
      transport: OraclePrimaryTransport(api, client: mock),
    );
    addTearDown(bridge.terminate);
    final document = bridge.doc('chatProfiles/owner');
    expect(
      (await document.get(
        const GetOptions(source: Source.server),
      )).data()?['value'],
      'postgres',
    );
    await document.set({
      'value': 'new',
      'changed': sdk.FieldValue.serverTimestamp(),
    });
    final batch = bridge.batch()..set('chatProfiles/owner', {'value': 'batch'});
    await batch.commit();
    expect(
      (await bridge
              .collection('chatProfiles')
              .count()
              .get(source: AggregateSource.server))
          .count,
      7,
    );
    unavailable = true;
    await expectLater(
      document.get(const GetOptions(source: Source.server)),
      throwsA(isA<OracleApiException>()),
    );
    expect(commits, 2);
    expect([native.gets, native.sets, native.batches], [0, 0, 0]);
  });

  test(
    'Primary transaction retries stale server versions without Firebase',
    () async {
      final directory = await Directory.systemTemp.createTemp('neural_tx_');
      addTearDown(() => _removeTestDirectory(directory));
      final native = _Native();
      var reads = 0;
      var commits = 0;
      final versions = <String>[];
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/commit')) {
          commits++;
          versions.add(
            (body['conditions'] as List).single['version'] as String,
          );
          return commits == 1
              ? http.Response('{"error":{"code":"aborted"}}', 409)
              : http.Response(
                  jsonEncode({
                    'requestId': body['requestId'],
                    'versions': {'chatProfiles/owner': '3'},
                    'commitTime': '2026-10-24T18:00:00.000000000Z',
                    'documents': [],
                  }),
                  200,
                );
        }
        reads++;
        return http.Response(
          jsonEncode({
            'row': {
              'path': 'chatProfiles/owner',
              'version': '$reads',
              'document': {
                'fields': {
                  'value': {'integerValue': '$reads'},
                },
              },
            },
          }),
          200,
        );
      });
      final api = OracleDataClient(token: () async => 'token', client: mock);
      final bridge = OracleFirestoreBridge(
        native,
        api,
        primary: true,
        uidProvider: () => 'owner',
        rootDirectory: () async => directory,
        transport: OraclePrimaryTransport(api, client: mock),
      );
      addTearDown(bridge.terminate);
      final result = await bridge.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get('chatProfiles/owner');
        final next = (snapshot.data()?['value'] as int) + 1;
        transaction.update('chatProfiles/owner', {
          FieldPath(['value']): next,
        });
        return next;
      });
      expect(result, 3);
      expect(versions, ['1', '2']);
      expect([native.gets, native.sets, native.batches], [0, 0, 0]);
    },
  );
  test(
    'Personal notes and files round trip through the VPS without native data calls',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'neural_personal_',
      );
      addTearDown(() => _removeTestDirectory(directory));
      final native = _Native(), rows = <String, Map<String, dynamic>>{};
      var uid = 'owner', revision = 0;
      late OracleFirestoreBridge bridge;
      final clock = Timestamp.fromDate(DateTime.utc(2026, 10, 24));
      const time = '2026-10-24T00:00:00.000000000Z';
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        Map<String, dynamic> result;
        if (request.url.path == '/v1/commit') {
          final versions = <String, dynamic>{},
              documents = <Map<String, dynamic>>[];
          for (final raw in body['operations'] as List) {
            final operation = Map<String, dynamic>.from(raw as Map),
                path = operation['path'] as String;
            final previous = rows[path];
            final data = applyOracleLocalWrite(
              previous == null
                  ? null
                  : bridge.codec.fields(previous['document']['fields'] as Map),
              operation,
              bridge.codec,
              clock,
            );
            if (data == null) {
              rows.remove(path);
              versions[path] = null;
              continue;
            }
            final row = <String, dynamic>{
              'path': path,
              'version': '${++revision}',
              'document': {
                'fields': data.map(
                  (k, v) => MapEntry(k, bridge.codec.encode(v)),
                ),
                'updateTime': time,
              },
            };
            rows[path] = row;
            versions[path] = row['version'];
            if (!path.contains('/chunks/')) documents.add(row);
          }
          result = {
            'requestId': body['requestId'],
            'versions': versions,
            'documents': documents,
            'commitTime': time,
          };
        } else if (body['kind'] == 'document') {
          result = {'row': rows[body['path']]};
        } else if (body['kind'] == 'documents') {
          result = {
            'rows': [
              for (final path in body['paths'] as List)
                if (rows[path] != null) rows[path],
            ],
          };
        } else {
          final query = body['query'] as Map;
          result = {
            'rows': [
              for (final row in rows.values)
                if ((row['path'] as String).substring(
                      0,
                      (row['path'] as String).lastIndexOf('/'),
                    ) ==
                    query['path'])
                  row,
            ],
          };
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = OracleDataClient(token: () async => 'token', client: mock);
      bridge = OracleFirestoreBridge(
        native,
        api,
        primary: true,
        uidProvider: () => uid,
        rootDirectory: () async => directory,
        transport: OraclePrimaryTransport(api, client: mock),
      );
      final previous = FirebaseFirestorePlatform.instance;
      FirebaseFirestorePlatform.instance = bridge;
      addTearDown(() async {
        await bridge.terminate();
        FirebaseFirestorePlatform.instance = previous;
      });
      final direct = DirectPersonalDb('owner', connection: bridge),
          personal = PersonalCloud('owner', store: direct);
      await personal.reconcile('news', {}, {
        'news_test': {'id': 'test', 'text': 'Private note'},
      });
      final remote = await personal.records('news');
      expect(remote['news_test']?['text'], 'Private note');
      final source = File('${directory.path}/source.bin'),
          destination = File('${directory.path}/restored.bin');
      final bytes = List<int>.generate(2000, (i) => i % 256);
      await source.writeAsBytes(bytes);
      await personal.saveFile('file_test', source);
      expect(await personal.restoreFile('file_test', destination), true);
      expect(await destination.readAsBytes(), bytes);
      expect(
        rows['chatAccounts/owner/personalFiles/file_test/chunks/0']?['document']['fields']['bytes']['bytesValue'],
        isNot(base64Encode(bytes)),
      );
      uid = 'other';
      await expectLater(personal.records('news'), throwsA(isA<StateError>()));
      uid = 'owner';
      await personal.removeFile('file_test');
      expect(rows.keys.where((p) => p.contains('/personalFiles/')), isEmpty);
      expect([native.gets, native.sets, native.batches], [0, 0, 0]);
    },
  );
}
