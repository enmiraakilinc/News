import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'oracle_client.dart';
import 'oracle_primary_transport.dart';

bool _large(dynamic value) {
  if (value is String) return value.length > 8192;
  if (value is Map) return value.values.any(_large);
  if (value is List) return value.any(_large);
  return false;
}

String _encodeBody(Map<String, dynamic> value) => jsonEncode(value);
Map<String, dynamic> _decodeBody(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

String oracleRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class OraclePendingWrite {
  final Map<String, dynamic> body;
  final String encoded;
  final File file;
  final acknowledged = Completer<Map<String, dynamic>>();
  bool running = false;
  DateTime retryAt = DateTime.fromMillisecondsSinceEpoch(0);
  OraclePendingWrite(this.body, this.encoded, this.file) {
    acknowledged.future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
  }
  String get id => body['requestId'] as String;
  bool get heavy => encoded.length > 65536;
  List<Map<String, dynamic>> get operations => (body['operations'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  DateTime get created =>
      DateTime.fromMillisecondsSinceEpoch(body['localCreatedAt'] as int);
  Iterable<String> get keys => operations.map((op) {
    final p = (op['path'] as String).split('/');
    if (p.length == 4 &&
        (p[0] == 'chats' && p[2] == 'messages' ||
            p[0] == 'couples' && p[2] == 'letters')) {
      return p.take(3).join('/');
    }
    return op['path'] as String;
  });
}

/// Durable, UID-scoped writes. One media lane leaves a lane free for text.
/// The operation future completes only after the VPS commits and acknowledges.
class OracleOutbox {
  final String uid;
  final bool Function() isCurrent;
  final Future<Directory> Function() directory;
  final OraclePrimaryTransport transport;
  final void Function() onChanged;
  final void Function(OraclePendingWrite, Map<String, dynamic>) onCommitted;
  final _records = <OraclePendingWrite>[];
  Future<void>? _loading;
  Directory? _folder;
  int _order = 0;
  Timer? _retry;
  bool enabled = true, _closed = false;
  OracleOutbox({
    required this.uid,
    required this.isCurrent,
    required this.directory,
    required this.transport,
    required this.onChanged,
    required this.onCommitted,
  });

  List<OraclePendingWrite> get pending => List.unmodifiable(_records);
  Future<void> initialize() => _loading ??= _load();
  Future<void> _load() async {
    _folder = Directory('${(await directory()).path}/outbox');
    await _folder!.create(recursive: true);
    final files = await _folder!
        .list()
        .where((v) => v is File && v.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final encoded = await file.readAsString();
      final body = encoded.length > 65536
          ? await compute(_decodeBody, encoded)
          : _decodeBody(encoded);
      if (body['actorUid'] != uid ||
          body['operations'] is! List ||
          body['localCreatedAt'] is! int) {
        throw const FormatException('Bekleyen gönderim kaydı okunamadı.');
      }
      _records.add(OraclePendingWrite(body, encoded, file));
      final order =
          int.tryParse(file.uri.pathSegments.last.split('_').first) ?? 0;
      if (order > _order) _order = order;
    }
    _pump();
  }

  Future<Map<String, dynamic>> enqueue(
    List<Map<String, dynamic>> operations,
  ) async {
    await initialize();
    if (!isCurrent()) throw OracleApiException(401, 'unauthenticated');
    final body = <String, dynamic>{
      'requestId': oracleRequestId(),
      'actorUid': uid,
      'clientCode': 2081,
      'localCreatedAt': DateTime.now().millisecondsSinceEpoch,
      'operations': operations,
    };
    final encoded = _large(body)
        ? await compute(_encodeBody, body)
        : _encodeBody(body);
    if (encoded.length > 8 * 1024 * 1024 ||
        _records.fold<int>(0, (n, r) => n + r.encoded.length) + encoded.length >
            256 * 1024 * 1024) {
      throw OracleApiException(
        413,
        'resource-exhausted',
        'Bekleyen dosyalar çok fazla. Gönderimlerin tamamlanmasını bekle.',
      );
    }
    _order = max(_order + 1, DateTime.now().microsecondsSinceEpoch);
    final filename =
        '${_order.toString().padLeft(20, '0')}_${body['requestId'] as String}.json';
    final file = File('${_folder!.path}/$filename'),
        temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    await temporary.rename(file.path);
    final record = OraclePendingWrite(body, encoded, file);
    _records.add(record);
    onChanged();
    _pump();
    return record.acknowledged.future;
  }

  bool _conflict(OraclePendingWrite a, OraclePendingWrite b) => a.keys.any(
    (x) =>
        b.keys.any((y) => x == y || x.startsWith('$y/') || y.startsWith('$x/')),
  );

  void _pump() {
    if (_closed || !enabled || !isCurrent()) return;
    final active = _records.where((r) => r.running).toList();
    final now = DateTime.now();
    while (active.length < 2) {
      OraclePendingWrite? selected;
      final ordered = [..._records]
        ..sort((a, b) {
          if (a.heavy != b.heavy) return a.heavy ? 1 : -1;
          return a.file.path.compareTo(b.file.path);
        });
      for (final record in ordered) {
        if (record.running ||
            record.retryAt.isAfter(now) ||
            record.heavy && active.any((r) => r.heavy)) {
          continue;
        }
        final index = _records.indexOf(record);
        if (_records.take(index).any((r) => _conflict(record, r))) continue;
        selected = record;
        break;
      }
      if (selected == null) break;
      selected.running = true;
      active.add(selected);
      unawaited(_send(selected));
    }
    if (_records.any((r) => !r.running)) {
      _retry ??= Timer(const Duration(seconds: 2), () {
        _retry = null;
        _pump();
      });
    }
  }

  Future<void> _send(OraclePendingWrite record) async {
    try {
      if (!isCurrent()) return;
      final response = await transport.post(
        '/v1/commit',
        record.body,
        encodedBody: record.encoded,
        timeout: const Duration(seconds: 120),
      );
      if (response['requestId'] != record.id || response['versions'] is! Map) {
        throw const FormatException('Gönderim onayı okunamadı.');
      }
      onCommitted(record, response);
      _records.remove(record);
      try {
        await record.file.delete();
      } on FileSystemException {
        /* Replay is idempotent if cleanup fails. */
      }
      if (!record.acknowledged.isCompleted) {
        record.acknowledged.complete(response);
      }
      onChanged();
    } catch (error, stack) {
      if (error is OracleApiException &&
          error.status >= 400 &&
          error.status < 500 &&
          ![401, 408, 409, 429].contains(error.status)) {
        _records.remove(record);
        try {
          await record.file.rename('${record.file.path}.failed');
        } on FileSystemException {
          /* Original durable copy is retained. */
        }
        if (!record.acknowledged.isCompleted) {
          record.acknowledged.completeError(error, stack);
        }
        onChanged();
      } else {
        record.retryAt = DateTime.now().add(const Duration(seconds: 2));
      }
    } finally {
      record.running = false;
      _pump();
    }
  }

  Future<void> waitForPendingWrites() async {
    await initialize();
    await Future.wait(_records.map((r) => r.acknowledged.future));
  }

  Future<Map<String, dynamic>> transaction(
    List<Map<String, dynamic>> operations,
    List<Map<String, dynamic>> conditions, {
    bool Function()? isActive,
  }) async {
    final body = <String, dynamic>{
      'requestId': oracleRequestId(),
      'actorUid': uid,
      'clientCode': 2081,
      'operations': operations,
      'conditions': conditions,
    };
    final encoded = _large(body)
        ? await compute(_encodeBody, body)
        : _encodeBody(body);
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!(isActive?.call() ?? true)) {
        throw OracleApiException(408, 'deadline-exceeded');
      }
      if (!isCurrent()) throw OracleApiException(401, 'unauthenticated');
      try {
        return await transport.post('/v1/commit', body, encodedBody: encoded);
      } catch (error) {
        if (error is OracleApiException &&
            error.status < 500 &&
            error.status != 429) {
          rethrow;
        }
        last = error;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    throw last ?? OracleApiException(503, 'unavailable');
  }

  void resume() {
    _retry?.cancel();
    _retry = null;
    _pump();
  }

  void close() {
    _closed = true;
    _retry?.cancel();
  }
}
