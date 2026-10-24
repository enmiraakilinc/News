import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/core/data/oracle_client.dart';
import 'package:flutter_application_1/core/data/oracle_codec.dart';
import 'package:flutter_application_1/core/data/oracle_local_values.dart';
import 'package:flutter_application_1/core/data/oracle_local_query.dart';
import 'package:flutter_application_1/core/data/oracle_primary_transport.dart';
import 'package:flutter_application_1/core/data/oracle_primary_store.dart';

class _Platform extends FirebaseFirestorePlatform {
  @override
  DocumentReferencePlatform doc(String path) => _Reference(this, path);
}

class _Reference extends DocumentReferencePlatform {
  _Reference(super.firestore, super.path);
}

final codec = OracleCodec(reference: _Platform().doc, project: 'star-galeri');
Map<String, dynamic> row(
  String path,
  String version,
  Map<String, dynamic> values, {
  String time = '2026-10-24T18:00:00.000000000Z',
}) => {
  'path': path,
  'version': version,
  'document': {
    'fields': values.map((k, v) => MapEntry(k, codec.encode(v))),
    'updateTime': time,
  },
};
Future<Directory> temporary() async {
  final dir = await Directory.systemTemp.createTemp('neural-store-test-');
  addTearDown(() async {
    final path = await dir.resolveSymbolicLinks(),
        root = await Directory.systemTemp.resolveSymbolicLinks();
    expect(path.startsWith(root + Platform.pathSeparator), true);
    expect(
      dir.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .startsWith('neural-store-test-'),
      true,
    );
    await dir.delete(recursive: true);
  });
  return dir;
}

class _Fixture {
  final Directory dir;
  final String uid;
  final List<StreamController<List<int>>> sources = [];
  final identity = OracleDataClient(token: () async => 'test-token');
  late final OraclePrimaryTransport transport;
  late final OraclePrimaryStore store;
  _Fixture(
    this.dir, {
    this.uid = 'alice',
    required Future<http.Response> Function(http.Request) handler,
    Map<String, dynamic>? initial,
  }) {
    transport = OraclePrimaryTransport(
      identity,
      client: MockClient(handler),
      streamClient: () => MockClient.streaming((request, stream) async {
        late StreamController<List<int>> source;
        source = StreamController<List<int>>(
          onListen: () {
            if (initial != null) {
              source.add(utf8.encode('data: ${jsonEncode(initial)}\n\n'));
            }
          },
        );
        sources.add(source);
        return http.StreamedResponse(source.stream, 200);
      }),
    );
    store = OraclePrimaryStore(
      uid: uid,
      isCurrent: () => true,
      codec: codec,
      transport: transport,
      rootDirectory: () async => dir,
    );
    addTearDown(() async {
      await store.close();
      for (final source in sources) {
        await source.close();
      }
      transport.close();
      identity.close();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Local pending transforms do not mutate previous snapshots', () {
    final old = {
      'nested': <String, dynamic>{'title': 'before'},
      'n': 2,
    };
    final operation = {
      'type': 'update',
      'fields': [
        {
          'field': ['nested', 'title'],
          'value': {'stringValue': 'after'},
        },
        {
          'field': ['n'],
          'value': {
            'transformValue': {
              'operation': 'increment',
              'value': {'integerValue': '1'},
            },
          },
        },
      ],
    };
    final result = applyOracleLocalWrite(
      old,
      operation,
      codec,
      Timestamp(1, 0),
    );
    expect((result!['nested'] as Map)['title'], 'after');
    expect((old['nested'] as Map)['title'], 'before');
    expect(result['n'], 3);
  });
  test(
    'Pending query order, document tie breaks, cursors and limits match the page',
    () {
      final rows = [
        row('chats/a/messages/a', '1', {'sentAt': Timestamp(5, 0)}),
        row('chats/a/messages/b', '2', {'sentAt': Timestamp(5, 0)}),
        row('chats/a/messages/c', '3', {'sentAt': Timestamp(6, 0)}),
      ];
      final query = <String, dynamic>{
        'path': 'chats/a/messages',
        'orders': [
          {
            'field': ['sentAt'],
            'descending': true,
          },
        ],
        'startAfter': [
          codec.encode(Timestamp(5, 0)),
          codec.encode(_Platform().doc('chats/a/messages/b')),
        ],
        'limit': 1,
      };
      expect(
        oracleLocalQuery(rows, query, codec).single['path'],
        'chats/a/messages/a',
      );
      expect(
        oracleLocalQuery(
          [
            ...rows,
            row('chats/other/messages/z', '4', {'sentAt': Timestamp(4, 0)}),
          ],
          query,
          codec,
        ).length,
        1,
      );
    },
  );
  test(
    'Cached data stays within one account and explicit server reads do not use cache offline',
    () async {
      final dir = await temporary(), path = 'chatAccounts/alice/contacts/bob';
      final fixture = _Fixture(
        dir,
        handler: (request) async => http.Response(
          jsonEncode({
            'row': row(path, '1', {'alias': 'Bob'}),
          }),
          200,
        ),
      );
      final request = <String, dynamic>{'kind': 'document', 'path': path};
      expect((await fixture.store.get(request)).fromCache, false);
      await fixture.store.setNetwork(false);
      await expectLater(
        fixture.store.get(request, serverOnly: true),
        throwsA(isA<OracleApiException>()),
      );
      expect(
        (await fixture.store.get(request, cacheOnly: true)).rows.single['path'],
        path,
      );
      final other = _Fixture(
        dir,
        uid: 'bob',
        handler: (request) async =>
            throw StateError('Cache-only read reached network'),
      );
      expect((await other.store.get(request, cacheOnly: true)).rows, isEmpty);
    },
  );
  test(
    'A pending message appears before the VPS acknowledgement and stays after it',
    () async {
      final dir = await temporary(),
          release = Completer<void>(),
          started = Completer<void>();
      final message = row('chats/direct/messages/one', '1', {
        'sender': 'alice',
        'text': 'hello',
        'sentAt': Timestamp(1792864800, 0),
      });
      final fixture = _Fixture(
        dir,
        initial: {'rows': []},
        handler: (request) async {
          final body = jsonDecode(request.body) as Map;
          started.complete();
          await release.future;
          return http.Response(
            jsonEncode({
              'requestId': body['requestId'],
              'commitTime': '2026-10-24T18:00:00.000000000Z',
              'versions': {'chats/direct/messages/one': '1'},
              'documents': [message],
            }),
            200,
          );
        },
      );
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final snapshots = <OracleStoreSnapshot>[];
      final sub = fixture.store
          .watch({
            'kind': 'query',
            'query': {
              'path': 'chats/direct/messages',
              'orders': [
                {
                  'field': ['sentAt'],
                  'descending': false,
                },
              ],
            },
          })
          .listen(snapshots.add);
      addTearDown(sub.cancel);
      while (snapshots.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final send = fixture.store.outbox.enqueue([
        {
          'type': 'set',
          'path': 'chats/direct/messages/one',
          'fields': {
            'sender': {'stringValue': 'alice'},
            'text': {'stringValue': 'hello'},
            'sentAt': {
              'transformValue': {'operation': 'serverTimestamp'},
            },
          },
        },
      ]);
      await started.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(snapshots.last.rows.single['path'], 'chats/direct/messages/one');
      expect(
        snapshots.last.pendingPaths,
        contains('chats/direct/messages/one'),
      );
      release.complete();
      await send;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(snapshots.last.rows.single['version'], '1');
      expect(snapshots.last.pendingPaths, isEmpty);
    },
  );
  test(
    'A stale acknowledgement cannot replace a more recent server value or deletion',
    () async {
      final dir = await temporary(), path = 'couples/pair/notes/counter';
      final newer = row(path, '8', {
        'n': 8,
      }, time: '2026-10-24T18:00:02.000000000Z');
      final fixture = _Fixture(
        dir,
        handler: (request) async =>
            http.Response(jsonEncode({'row': newer}), 200),
      );
      final request = <String, dynamic>{'kind': 'document', 'path': path};
      await fixture.store.get(request);
      fixture.store.acceptCommit(
        [
          {'type': 'delete', 'path': path},
        ],
        {
          'versions': {path: null},
          'commitTime': '2026-10-24T18:00:01.000000000Z',
          'documents': [],
        },
      );
      final result = await fixture.store.get(request, cacheOnly: true);
      expect(result.rows.single['version'], '8');
    },
  );
  test(
    'Cancelling a live view closes its stream and releases the store cleanly',
    () async {
      final dir = await temporary();
      final fixture = _Fixture(
        dir,
        initial: {'rows': []},
        handler: (request) async => throw StateError('Unexpected read'),
      );
      final initial = Completer<void>();
      final sub = fixture.store
          .watch({
            'kind': 'query',
            'query': {'path': 'chats', 'filters': []},
          })
          .listen((_) {
            if (!initial.isCompleted) initial.complete();
          });
      await initial.future;
      await sub.cancel().timeout(const Duration(seconds: 3));
      await fixture.store.close().timeout(const Duration(seconds: 3));
    },
  );
}
