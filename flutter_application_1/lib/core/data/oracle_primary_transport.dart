import 'dart:async';
import 'dart:convert';
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
    final response = await _http
        .post(
          identity.base.resolve(path),
          headers: await _headers(),
          body: encodedBody ?? jsonEncode(body),
        )
        .timeout(timeout);
    final value = await decodeOracleResponseAsync(response.bodyBytes);
    if (response.statusCode != 200) throw _error(response.statusCode, value);
    return Map<String, dynamic>.from(value);
  }

  Stream<Map<String, dynamic>> watch(Map<String, dynamic> body) {
    late final StreamController<Map<String, dynamic>> controller;
    http.Client? client;
    StreamSubscription<String>? lines;
    var cancelled = false;
    Future<void> cancel() async {
      if (cancelled) return;
      cancelled = true;
      client?.close();
      await lines?.cancel();
    }

    void end() {
      if (cancelled) return;
      unawaited(cancel().then((_) => controller.close()));
    }

    Future<void> connect() async {
      try {
        client = _streamClient();
        final headers = await _headers();
        if (cancelled) return;
        final request = http.Request('POST', identity.base.resolve('/v1/watch'))
          ..headers.addAll(headers)
          ..body = jsonEncode(body);
        final response = await client!
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (cancelled) return;
        if (response.statusCode != 200) {
          final data = await response.stream.bytesToString();
          throw _error(response.statusCode, jsonDecode(data));
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
                  if (!cancelled) controller.addError(error, stack);
                  end();
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!cancelled) controller.addError(error, stack);
                end();
              },
              onDone: end,
            );
        if (cancelled) await lines?.cancel();
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
        end();
      }
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(connect()),
      onCancel: cancel,
    );
    return controller.stream;
  }

  void close() => _http.close();
}
