import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_application_1/features/media/chat_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/core/data/oracle_media_batch.dart';
import 'package:flutter_application_1/features/media/private_media_stream.dart';

void main() {
  test(
    'Loopback video seeks without full download and rechecks permission for cached bytes',
    () async {
      var revoked = false;
      final loaded = <int>[];
      final source = await PrivateMediaStream.fromChunks(
        size: 20 * mediaChunkBytes,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        authorize: () async {
          if (revoked) throw const SocketException('revoked');
        },
        load: (int start, int count) async {
          loaded.addAll([for (var i = start; i < start + count; i++) i]);
          return [
            for (var i = start; i < start + count; i++)
              Uint8List(mediaChunkBytes)..fillRange(0, mediaChunkBytes, i),
          ];
        },
      );
      final client = HttpClient();
      try {
        final tail = await client.getUrl(source.uri);
        tail.headers.set('Range', 'bytes=-32');
        final response = await tail.close();
        expect(response.statusCode, 206);
        final bytes = await response.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        expect(bytes, List.filled(32, 19));
        expect(loaded.length, lessThan(20));
        final cross = await client.getUrl(source.uri);
        cross.headers.set(
          'Range',
          'bytes=${5 * mediaChunkBytes - 4}-${5 * mediaChunkBytes + 3}',
        );
        final crossing = await cross.close();
        expect(crossing.statusCode, 206);
        expect(await crossing.fold<List<int>>([], (a, b) => a..addAll(b)), [
          4,
          4,
          4,
          4,
          5,
          5,
          5,
          5,
        ]);
        final wrong = await client.getUrl(source.uri.replace(path: '/wrong'));
        final notFound = await wrong.close();
        expect(notFound.statusCode, 404);
        await notFound.drain<void>();
        revoked = true;
        final forbidden = await client.getUrl(source.uri);
        forbidden.headers.set(
          'Range',
          'bytes=${5 * mediaChunkBytes}-${5 * mediaChunkBytes + 3}',
        );
        final denied = await forbidden.close();
        expect(denied.statusCode, 403);
        await denied.drain<void>();
      } finally {
        client.close(force: true);
        await source.close();
      }
    },
  );
  test(
    'Binary media decodes exact encrypted bytes and rejects partial frames',
    () {
      final bytes = Uint8List(6 + 5 + 16 + 3),
          data = ByteData.sublistView(bytes);
      bytes.setRange(0, 4, 'NMC1'.codeUnits);
      data.setUint16(4, 1);
      data.setUint32(6, 3);
      bytes[10] = 16;
      bytes.fillRange(11, 27, 7);
      bytes.setRange(27, 30, [1, 2, 3]);
      final decoded = decodeBinaryMedia(bytes, 1).single;
      expect((decoded['bytes'] as Blob).bytes, [1, 2, 3]);
      expect((decoded['iv'] as Blob).bytes, List.filled(16, 7));
      expect(
        () => decodeBinaryMedia(bytes.sublist(0, 29), 1),
        throwsFormatException,
      );
      expect(() => decodeBinaryMedia(bytes, 2), throwsFormatException);
    },
  );
  test('Video ranges support seeking, suffixes and bound invalid requests', () {
    expect(mediaByteRange(null, 100), (start: 0, end: 99));
    expect(mediaByteRange('bytes=20-39', 100), (start: 20, end: 39));
    expect(mediaByteRange('bytes=90-', 100), (start: 90, end: 99));
    expect(mediaByteRange('bytes=-10', 100), (start: 90, end: 99));
    expect(mediaByteRange('bytes=100-', 100), null);
    expect(mediaByteRange('bytes=50-20', 100), null);
    expect(mediaByteRange('bytes=0-1,10-20', 100), null);
  });
}
