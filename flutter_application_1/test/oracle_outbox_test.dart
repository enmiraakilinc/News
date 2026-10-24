import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/core/data/oracle_client.dart';
import 'package:flutter_application_1/core/data/oracle_primary_transport.dart';
import 'package:flutter_application_1/core/data/oracle_outbox.dart';

Future<Directory> tempFolder() async {
  final dir = await Directory.systemTemp.createTemp('neural-outbox-test-');
  addTearDown(() async {
    final actual = await dir.resolveSymbolicLinks();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    expect(actual.startsWith(root + Platform.pathSeparator), isTrue);
    expect(
      dir.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .startsWith('neural-outbox-test-'),
      isTrue,
    );
    await dir.delete(recursive: true);
  });
  return dir;
}

Map<String, dynamic> operation(String path, [String text = 'hello']) => {
  'type': 'set',
  'path': path,
  'fields': {
    'text': {'stringValue': text},
  },
};
http.Response acknowledged(Map body) => http.Response(
  jsonEncode({
    'requestId': body['requestId'],
    'commitTime': '2026-10-24T18:00:00.000000000Z',
    'versions': {for (final op in body['operations'] as List) op['path']: '1'},
    'documents': [],
  }),
  200,
);
OraclePrimaryTransport transport(
  Future<http.Response> Function(http.Request) handler,
) => OraclePrimaryTransport(
  OracleDataClient(token: () async => 'test-token'),
  client: MockClient(handler),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'A persisted write replays with the same identity after a lost connection',
    () async {
      final dir = await tempFolder(), attempted = Completer<Map>();
      final first = transport((request) async {
        attempted.complete(jsonDecode(request.body) as Map);
        throw http.ClientException('offline');
      });
      addTearDown(first.close);
      final initial = OracleOutbox(
        uid: 'alice',
        isCurrent: () => true,
        directory: () async => dir,
        transport: first,
        onChanged: () {},
        onCommitted: (_, response) {},
      );
      addTearDown(initial.close);
      unawaited(initial.enqueue([operation('chats/a/messages/1')]));
      final body = await attempted.future;
      initial.close();
      final files = await Directory('${dir.path}/outbox').list().toList();
      expect(files.whereType<File>().length, 1);
      expect(body['actorUid'], 'alice');
      final committed = Completer<Map>();
      final second = transport((request) async {
        final retry = jsonDecode(request.body) as Map;
        expect(retry['requestId'], body['requestId']);
        expect(retry['actorUid'], 'alice');
        return acknowledged(retry);
      });
      addTearDown(second.close);
      final restored = OracleOutbox(
        uid: 'alice',
        isCurrent: () => true,
        directory: () async => dir,
        transport: second,
        onChanged: () {},
        onCommitted: (_, response) => committed.complete(response),
      );
      addTearDown(restored.close);
      await restored.initialize();
      await restored.waitForPendingWrites();
      expect((await committed.future)['requestId'], body['requestId']);
      expect(restored.pending, isEmpty);
    },
  );
  test('A large media request leaves a separate lane for text', () async {
    final dir = await tempFolder(),
        heavyStarted = Completer<void>(),
        release = Completer<void>();
    final client = transport((request) async {
      final body = jsonDecode(request.body) as Map;
      if (request.body.length > 65536) {
        heavyStarted.complete();
        await release.future;
      }
      return acknowledged(body);
    });
    addTearDown(client.close);
    final outbox = OracleOutbox(
      uid: 'alice',
      isCurrent: () => true,
      directory: () async => dir,
      transport: client,
      onChanged: () {},
      onCommitted: (_, response) {},
    );
    addTearDown(outbox.close);
    final heavy = outbox.enqueue([
      operation('chatMedia/file/chunks/0', 'x' * 70000),
    ]);
    await heavyStarted.future;
    final text = outbox.enqueue([operation('chats/direct/messages/1')]);
    await text.timeout(const Duration(seconds: 5));
    expect(release.isCompleted, false);
    release.complete();
    await heavy;
  });
  test('Changing accounts pauses the previous users queue', () async {
    final dir = await tempFolder(), attempted = Completer<void>();
    var active = true, calls = 0;
    final offline = transport((request) async {
      attempted.complete();
      throw http.ClientException('offline');
    });
    addTearDown(offline.close);
    final initial = OracleOutbox(
      uid: 'alice',
      isCurrent: () => active,
      directory: () async => dir,
      transport: offline,
      onChanged: () {},
      onCommitted: (_, response) {},
    );
    addTearDown(initial.close);
    unawaited(initial.enqueue([operation('chats/a/messages/1')]));
    await attempted.future;
    active = false;
    initial.close();
    final online = transport((request) async {
      calls++;
      return acknowledged(jsonDecode(request.body) as Map);
    });
    addTearDown(online.close);
    final restored = OracleOutbox(
      uid: 'alice',
      isCurrent: () => active,
      directory: () async => dir,
      transport: online,
      onChanged: () {},
      onCommitted: (_, response) {},
    );
    addTearDown(restored.close);
    await restored.initialize();
    restored.resume();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, 0);
    expect(restored.pending.length, 1);
    active = true;
    restored.resume();
    await restored.waitForPendingWrites();
    expect(calls, 1);
  });
  test(
    'Permission denial is reported as failure and preserves a recovery copy',
    () async {
      final dir = await tempFolder();
      final client = transport(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'permission-denied',
              'message': 'Bu alana erişim iznin yok.',
            },
          }),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.post('/v1/commit', {}),
        throwsA(
          isA<OracleApiException>().having((e) => e.status, 'status', 403),
        ),
      );
      final outbox = OracleOutbox(
        uid: 'alice',
        isCurrent: () => true,
        directory: () async => dir,
        transport: client,
        onChanged: () {},
        onCommitted: (_, response) {
          fail('Denied write was accepted');
        },
      );
      addTearDown(outbox.close);
      await expectLater(
        outbox.enqueue([operation('chats/other/messages/1')]),
        throwsA(
          isA<OracleApiException>().having((e) => e.status, 'status', 403),
        ),
      );
      expect(outbox.pending, isEmpty);
      expect(
        (await Directory(
          '${dir.path}/outbox',
        ).list().toList()).single.path.endsWith('.failed'),
        true,
      );
    },
  );
  test(
    'SSE payloads survive partial UTF-8 delivery and authorization is in headers',
    () async {
      final body =
          'data: ${jsonEncode({
            'rows': [
              {'title': 'Görüşme'},
            ],
          })}\n\n';
      final bytes = utf8.encode(body);
      final identity = OracleDataClient(token: () async => 'test-token');
      final client = OraclePrimaryTransport(
        identity,
        streamClient: () => MockClient.streaming((request, stream) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.url.query, isEmpty);
          return http.StreamedResponse(
            Stream.fromIterable([
              bytes.sublist(0, 17),
              bytes.sublist(17, 19),
              bytes.sublist(19),
            ]),
            200,
          );
        }),
      );
      addTearDown(client.close);
      addTearDown(identity.close);
      final events = await client.watch({
        'kind': 'query',
        'query': {'path': 'chats'},
      }).toList();
      expect((events.single['rows'] as List).single['title'], 'Görüşme');
    },
  );
}
