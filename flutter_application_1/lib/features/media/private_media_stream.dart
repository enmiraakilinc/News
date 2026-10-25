import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../pair/couple_service.dart';
import 'chat_media.dart';

({int start, int end})? mediaByteRange(String? header, int size) {
  if (size < 1) return null;
  if (header == null) return (start: 0, end: size - 1);
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
  if (match == null || match[1]!.isEmpty && match[2]!.isEmpty) return null;
  final first = int.tryParse(match[1]!), last = int.tryParse(match[2]!);
  final start = first ?? max(0, size - (last ?? 0));
  final end = first == null ? size - 1 : min(size - 1, last ?? size - 1);
  return start >= 0 && start < size && end >= start
      ? (start: start, end: end)
      : null;
}

/// A short-lived loopback reader: only requested, individually decrypted pieces
/// reach the player. No Firebase token/secret leaves the phone in its URL.
class PrivateMediaStream {
  final String _token;
  final int size, count;
  final Future<void> Function() _authorize;
  final Future<List<Uint8List>> Function(int, int) _load;
  final HttpServer _server;
  final _cache = <int, Uint8List>{};
  final _pending = <int, Future<List<Uint8List>>>{};
  Timer? _expiry;
  bool _closed = false;
  PrivateMediaStream._(
    this._token,
    this.size,
    this.count,
    this._server,
    this._authorize,
    this._load,
  );
  Uri get uri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _server.port,
    path: '/$_token',
  );

  static Future<PrivateMediaStream> open(String id) async {
    final scope = await ChatMedia.accessScope();
    await ChatMedia.checkAccess(id);
    final data = await ChatMedia.expiryInfo(id);
    final size = data['size'] as int, count = data['chunks'] as int;
    if (!['video', 'file'].contains(data['kind']) ||
        size < 1 ||
        size > maxChatVideoBytes ||
        count != (size / mediaChunkBytes).ceil()) {
      throw Exception('Geçersiz video.');
    }
    final secret = data['coupleId'] == null
        ? null
        : await CoupleService.secret();
    if (await ChatMedia.accessScope() != scope) {
      throw Exception('Hesap değişti. Yeniden aç.');
    }
    return fromChunks(
      size: size,
      expiresAt: chatMediaExpiresAt(data),
      authorize: () async {
        if (await ChatMedia.accessScope() != scope) {
          throw const SocketException('Hesap değişti.');
        }
        await ChatMedia.checkAccess(id);
      },
      load: (start, count) async {
        final chunks=await ChatMedia.decodedChunks(id,start,count,secret:secret);
        if(await ChatMedia.accessScope()!=scope)throw const SocketException('Hesap değişti.');
        return chunks;
      },
    );
  }

  /// Range reader engine, also usable with a deterministic source in tests.
  static Future<PrivateMediaStream> fromChunks({
    required int size,
    required DateTime expiresAt,
    required Future<void> Function() authorize,
    required Future<List<Uint8List>> Function(int, int) load,
  }) async {
    if (size < 1 || size > maxChatVideoBytes) {
      throw const FormatException('Geçersiz video boyutu.');
    }
    await authorize();
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final random = Random.secure();
    final token = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final result = PrivateMediaStream._(
      token,
      size,
      (size / mediaChunkBytes).ceil(),
      server,
      authorize,
      load,
    );
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await result.close();
      throw Exception('Videonun erişim süresi dolmuş.');
    }
    result._expiry = Timer(remaining, () => unawaited(result.close()));
    server.listen(
      (request) => unawaited(result._serve(request)),
      onError: (_) => unawaited(result.close()),
    );
    return result;
  }

  Future<Uint8List> _chunk(int index) async {
    if (_closed) throw const SocketException('Video kapatıldı.');
    final hit = _cache.remove(index);
    if (hit != null) {
      _cache[index] = hit;
      return hit;
    }
    // Start playback/tail metadata with one piece; read ahead only afterwards.
    final start = index;
    final future = _pending.putIfAbsent(
      start,
      () => _load(start, index==0?1:min(4, count - start)),
    );
    try {
      final chunks = await future;
      if (_closed) throw const SocketException('Video kapatıldı.');
      for (var i = 0; i < chunks.length; i++) {
        final expected = min(
          mediaChunkBytes,
          size - (start + i) * mediaChunkBytes,
        );
        if (chunks[i].length != expected) {
          throw const FormatException('Eksik video parçası.');
        }
        _cache.remove(start + i);
        _cache[start + i] = chunks[i];
      }
      while (_cache.length > 8) {
        _cache.remove(_cache.keys.first);
      }
      return chunks[index - start];
    } finally {
      if (identical(_pending[start], future)) _pending.remove(start);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (_closed ||
          request.uri.path != '/$_token' ||
          !['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      await _authorize();
      final range = mediaByteRange(
        request.headers.value(HttpHeaders.rangeHeader),
        size,
      );
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType('video', 'mp4');
      if (range == null) {
        response.statusCode = 416;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        await response.close();
        return;
      }
      response.statusCode =
          request.headers.value(HttpHeaders.rangeHeader) == null ? 200 : 206;
      if (response.statusCode == 206) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.end}/$size',
        );
      }
      response.contentLength = range.end - range.start + 1;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      var cancelled = false;
      unawaited(
        response.done.then<void>(
          (_) => cancelled = true,
          onError: (Object _) => cancelled = true,
        ),
      );
      for (
        var index = range.start ~/ mediaChunkBytes;
        index <= range.end ~/ mediaChunkBytes;
        index++
      ) {
        if (cancelled || _closed) break;
        final bytes = await _chunk(index);
        final first = max(0, range.start - index * mediaChunkBytes);
        final last = min(bytes.length, range.end - index * mediaChunkBytes + 1);
        response.add(Uint8List.sublistView(bytes, first, last));
        await response.flush();
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.forbidden;
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry?.cancel();
    _cache.clear();
    _pending.clear();
    await _server.close(force: true);
  }
}
