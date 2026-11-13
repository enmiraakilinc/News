import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'oracle_client.dart';

/// HTTPS transport for the primary store. No token is persisted or put in URLs.
class OraclePrimaryTransport {
  final OracleDataClient identity;
  final http.Client _http;
  final http.Client Function() _streamClient;
  OraclePrimaryTransport(
    this.identity, {
    http.Client? client,
    http.Client Function()? streamClient,
  }) : _http = client ?? http.Client(),
       _streamClient = streamClient ?? http.Client.new;

  Future<Map<String, String>> _headers() async {
    final token = await identity.token();
    if (token == null) throw OracleApiException(401, 'unauthenticated');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  OracleApiException _error(int status, dynamic body) {
    final error = body is Map ? body['error'] : null;
    return OracleApiException(
      status,
      error is Map ? error['code'] as String? ?? 'unavailable' : 'unavailable',
      error is Map ? error['message'] as String? : null,
    );
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
    String? encodedBody,
  }) async {
    return (() async {
      final response = await _http.post(
        identity.base.resolve(path),
        headers: await _headers(),
        body: encodedBody ?? jsonEncode(body),
      );
      final value = await decodeOracleResponseAsync(response.bodyBytes);
      if (response.statusCode != 200) throw _error(response.statusCode, value);
      return Map<String, dynamic>.from(value);
    })().timeout(timeout);
  }

  Stream<Map<String, dynamic>> watch(Map<String, dynamic> body) {
    late final StreamController<Map<String, dynamic>> controller;
    http.Client? client;
    StreamSubscription<String>? lines;
    var cancelled = false;
    var stopped = false;
    Future<void> release() async {
      final current = client;
      final subscription = lines;
      client = null;
      lines = null;
      current?.close();
      await subscription?.cancel();
    }

    Future<void> cancel() async {
      if (stopped) return;
      stopped = true;
      cancelled = true;
      await release();
    }

    void end() {
      if (stopped) return;
      stopped = true;
      cancelled = true;
      unawaited(
        release().then((_) {
          if (!controller.isClosed) controller.close();
        }),
      );
    }

    void fail(Object error, StackTrace stack) {
      if (stopped) return;
      final denied =
          error is OracleApiException &&
          (error.status == 401 || error.status == 403);
      if (denied && !controller.isClosed) controller.addError(error, stack);
      end();
    }

    Future<void> connect() async {
      try {
        client = _streamClient();
        final headers = await _headers().timeout(const Duration(seconds: 20));
        if (cancelled) return;
        final request = http.Request('POST', identity.base.resolve('/v1/watch'))
          ..headers.addAll(headers)
          ..body = jsonEncode(body);
        final response = await client!
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (cancelled) return;
        if (response.statusCode != 200) {
          Object? decoded;
          try {
            decoded = jsonDecode(await response.stream.bytesToString());
          } catch (_) {}
          throw _error(response.statusCode, decoded);
        }
        var event = '';
        final data = <String>[];
        lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 45))
            .listen(
              (line) {
                if (cancelled) return;
                try {
                  if (line.isEmpty) {
                    if (data.isNotEmpty) {
                      final value = jsonDecode(data.join('\n'));
                      if (event == 'failure') throw _error(503, value);
                      if (value is! Map) {
                        throw const FormatException('Sunucu akışı okunamadı.');
                      }
                      controller.add(Map<String, dynamic>.from(value));
                    }
                    event = '';
                    data.clear();
                  } else if (line.startsWith('data:')) {
                    data.add(line.substring(5).trimLeft());
                  } else if (line.startsWith('event:')) {
                    event = line.substring(6).trim();
                  }
                } catch (error, stack) {
                  fail(error, stack);
                }
              },
              onError: fail,
              onDone: end,
            );
        if (cancelled) await lines?.cancel();
      } catch (error, stack) {
        fail(error, stack);
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(connect()),
      onCancel: cancel,
    );
    return controller.stream;
  }

  Future<Uint8List> mediaBytes(List<String> paths) async {
    final response = await _http
        .post(
          identity.base.resolve('/v1/media/chunks'),
          headers: await _headers(),
          body: jsonEncode({'paths': paths}),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      dynamic error;
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw _error(response.statusCode, error);
    }
    if (response.bodyBytes.length > 16 * 460850 + 6) {
      throw const FormatException('Medya yanıtı çok büyük.');
    }
    return response.bodyBytes;
  }

  void close() => _http.close();
}
