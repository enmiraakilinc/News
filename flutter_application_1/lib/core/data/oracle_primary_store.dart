import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'oracle_client.dart';
import 'oracle_codec.dart';
import 'oracle_local_query.dart';
import 'oracle_local_values.dart';
import 'oracle_outbox.dart';
import 'oracle_primary_transport.dart';

String _encodeCache(Map<String, dynamic> value) => jsonEncode(value);
Map<String, dynamic> _decodeCache(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);
int _size(dynamic value) {
  if (value is String) return value.length * 2;
  if (value is List) return value.fold(0, (n, v) => n + _size(v));
  if (value is Map) {
    return value.entries.fold(0, (n, e) => n + _size(e.key) + _size(e.value));
  }
  return 16;
}

class OracleStoreSnapshot {
  final List<Map<String, dynamic>> rows;
  final bool fromCache;
  final Set<String> pendingPaths;
  OracleStoreSnapshot(this.rows, this.fromCache, this.pendingPaths);
}

class _View {
  final Map<String, dynamic> request;
  List<Map<String, dynamic>> rows = [];
  bool ready = false, fromCache = true;
  _View(this.request);
}

/// One instance per authenticated UID. Files and in-memory data never cross UIDs.
class OraclePrimaryStore {
  final String uid;
  final bool Function() isCurrent;
  final OracleCodec codec;
  final OraclePrimaryTransport transport;
  final Future<Directory> Function()? rootDirectory;
  final _changes = StreamController<void>.broadcast();
  final _memory = <String, Map<String, dynamic>>{};
  final _views = <_View>{};
  final _cancellations = <Future<void> Function()>{};
  final _diskPending = <String, Map<String, dynamic>>{};
  Future<void>? _loading;
  Future<Directory>? _folder;
  Future<void> _cacheIo = Future.value();
  Timer? _cacheTimer;
  bool networkEnabled = true, _closed = false;
  late final outbox = OracleOutbox(
    uid: uid,
    isCurrent: () => isCurrent() && !_closed,
    directory: _directory,
    transport: transport,
    onChanged: _notify,
    onCommitted: (record, response) =>
        acceptCommit(record.operations, response),
  );
  OraclePrimaryStore({
    required this.uid,
    required this.isCurrent,
    required this.codec,
    required this.transport,
    this.rootDirectory,
  });
  Stream<void> get changes => _changes.stream;
  Future<Directory> _directory() => _folder ??= () async {
    final root =
        await (rootDirectory?.call() ?? getApplicationSupportDirectory());
    final scope = sha256.convert(utf8.encode(uid)).toString();
    final folder = Directory('${root.path}/neural_primary_v2/$scope');
    await Directory('${folder.path}/cache').create(recursive: true);
    return folder;
  }();
  Future<void> initialize() => _loading ??= outbox.initialize();
  void _guard() {
    if (_closed) throw StateError('Veri bağlantısı kapalı.');
    if (!isCurrent()) throw OracleApiException(401, 'unauthenticated');
  }

  void notifyCommitted() => _notify();
  void _notify() {
    if (!_closed) _changes.add(null);
  }

  String _key(Map request) => request['kind'] == 'document'
      ? 'd:${request['path']}'
      : 'q:${jsonEncode(request['query'])}';
  List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
  bool _cacheable(Map request) {
    final path = request['kind'] == 'document'
        ? request['path'] as String
        : request['query']['path'] as String;
    final p = path.split('/');
    if (p[0] == 'sharedLocations') return false;
    final collection = request['kind'] == 'document' ? p[p.length - 2] : p.last;
    return collection != 'chunks' && collection != 'preview';
  }

  Future<File> _cacheFile(String key) async => File(
    '${(await _directory()).path}/cache/${sha256.convert(utf8.encode(key))}.json',
  );
  Future<Map<String, dynamic>?> _cached(Map<String, dynamic> request) async {
    final key = _key(request);
    if (_memory.containsKey(key)) return _memory[key];
    if (!_cacheable(request)) return null;
    try {
      final file = await _cacheFile(key);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      final entry = text.length > 65536
          ? await compute(_decodeCache, text)
          : _decodeCache(text);
      if (entry['uid'] != uid ||
          entry['savedAt'] is! int ||
          DateTime.now().millisecondsSinceEpoch - (entry['savedAt'] as int) >
              7 * 86400000) {
        return null;
      }
      _memory[key] = entry;
      return entry;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  void _cache(Map<String, dynamic> request, List<Map<String, dynamic>> rows) {
    if (_closed || !_cacheable(request)) return;
    final key = _key(request);
    final entry = <String, dynamic>{
      'uid': uid,
      'request': request,
      'rows': rows,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (_size(entry) > 32 * 1024 * 1024) return;
    _memory.remove(key);
    _memory[key] = entry;
    while (_memory.length > 24 ||
        _memory.values.fold<int>(0, (n, v) => n + _size(v)) >
            32 * 1024 * 1024) {
      _memory.remove(_memory.keys.first);
    }
    _diskPending[key] = entry;
    _cacheTimer ??= Timer(const Duration(milliseconds: 400), () {
      _cacheTimer = null;
      _cacheIo = _cacheIo
          .then((_) => _flushCache())
          .catchError((Object _, StackTrace _) {});
    });
  }

  Future<void> _flushCache() async {
    final pending = Map<String, Map<String, dynamic>>.from(_diskPending);
    _diskPending.clear();
    for (final entry in pending.entries) {
      try {
        final text = await compute(_encodeCache, entry.value);
        final file = await _cacheFile(entry.key),
            temporary = File('${file.path}.tmp');
        await temporary.writeAsString(text);
        await temporary.rename(file.path);
      } on FileSystemException {
        /* Cache failure never loses the durable outbox. */
      }
    }
    final folder = Directory('${(await _directory()).path}/cache');
    final files = await folder
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final stats = <MapEntry<File, FileStat>>[];
    for (final file in files) {
      stats.add(MapEntry(file, await file.stat()));
    }
    stats.sort((a, b) => b.value.modified.compareTo(a.value.modified));
    var bytes = 0;
    for (var i = 0; i < stats.length; i++) {
      bytes += stats[i].value.size;
      if (i >= 64 ||
          bytes > 128 * 1024 * 1024 ||
          DateTime.now().difference(stats[i].value.modified).inDays >= 7) {
        try {
          await stats[i].key.delete();
        } on FileSystemException {
          /* Optional cache. */
        }
      }
    }
  }

  Map<String, dynamic>? _known(String path) {
    Map<String, dynamic>? found;
    void consider(Map<String, dynamic> row) {
      if (row['path'] != path) return;
      final n =
          BigInt.tryParse(row['version']?.toString() ?? '') ?? BigInt.zero;
      final old =
          BigInt.tryParse(found?['version']?.toString() ?? '') ?? BigInt.zero;
      if (found == null || n >= old) found = row;
    }

    for (final entry in _memory.values) {
      for (final row in _rows(entry['rows'])) {
        consider(row);
      }
    }
    for (final view in _views) {
      for (final row in view.rows) {
        consider(row);
      }
    }
    return found;
  }

  Map<String, dynamic>? _apply(
    Map<String, dynamic>? row,
    Map<String, dynamic> op,
    Timestamp clock,
    String version,
  ) {
    final old = row == null
        ? null
        : codec.fields(row['document']['fields'] as Map? ?? {});
    final value = applyOracleLocalWrite(old, op, codec, clock);
    if (value == null) return null;
    return {
      'path': op['path'],
      'version': version,
      'document': {
        'updateTime': codec.encode(clock)['timestampValue'],
        'fields': value.map((k, v) => MapEntry(k, codec.encode(v))),
      },
    };
  }

  OracleStoreSnapshot _snapshot(_View view, {bool includePending = true}) {
    final rows = {for (final row in view.rows) row['path'] as String: row};
    final paths = <String>{};
    final query = view.request['query'] as Map<String, dynamic>?;
    for (final record
        in includePending ? outbox.pending : <OraclePendingWrite>[]) {
      for (final op in record.operations) {
        final path = op['path'] as String;
        final relevant = query != null
            ? path.substring(0, path.lastIndexOf('/')) == query['path']
            : path == view.request['path'];
        if (!relevant) continue;
        paths.add(path);
        final row = _apply(
          rows[path] ?? _known(path),
          op,
          Timestamp.fromDate(record.created),
          'local:${record.id}',
        );
        if (row == null) {
          rows.remove(path);
        } else {
          rows[path] = row;
        }
      }
    }
    final selected = query == null
        ? rows.values.toList()
        : oracleLocalQuery(rows.values, query, codec);
    return OracleStoreSnapshot(selected, view.fromCache, paths);
  }

  Future<OracleStoreSnapshot> get(
    Map<String, dynamic> request, {
    bool cacheOnly = false,
    bool serverOnly = false,
    bool includePending = true,
  }) async {
    await initialize();
    _guard();
    final view = _View(request), cached = await _cached(request);
    if (!networkEnabled && serverOnly) {
      throw OracleApiException(503, 'unavailable');
    }
    if (cacheOnly || !networkEnabled) {
      view.rows = _rows(cached?['rows']);
      view.ready = true;
      return _snapshot(view, includePending: includePending);
    }
    try {
      final data = await transport.post('/v1/read', request);
      _guard();
      view.rows = request['kind'] == 'document'
          ? (data['row'] == null
                ? []
                : [Map<String, dynamic>.from(data['row'] as Map)])
          : _rows(data['rows']);
      view.ready = true;
      view.fromCache = false;
      _cache(request, view.rows);
      return _snapshot(view, includePending: includePending);
    } catch (error) {
      final allowed =
          error is! OracleApiException ||
          error.status >= 500 ||
          error.status == 429;
      if (serverOnly || !allowed || cached == null) rethrow;
      view.rows = _rows(cached['rows']);
      view.ready = true;
      return _snapshot(view, includePending: includePending);
    }
  }

  Future<int> count(Map<String, dynamic> query) async {
    await initialize();
    _guard();
    if (!networkEnabled) throw OracleApiException(503, 'unavailable');
    final response = await transport.post('/v1/read', {
      'kind': 'count',
      'query': query,
    });
    _guard();
    return response['count'] as int;
  }

  void acceptCommit(
    List<Map<String, dynamic>> operations,
    Map<String, dynamic> response,
  ) {
    final versions = Map<String, dynamic>.from(response['versions'] as Map);
    final full = {
      for (final row in _rows(response['documents']))
        row['path'] as String: row,
    };
    final clock =
        codec.decode({'timestampValue': response['commitTime']}) as Timestamp;
    final updates = <String, Map<String, dynamic>?>{};
    for (final op in operations) {
      final path = op['path'] as String, known = _known(path);
      final current =
          BigInt.tryParse(known?['version']?.toString() ?? '') ?? BigInt.zero;
      final acknowledged =
          BigInt.tryParse(versions[path]?.toString() ?? '') ?? BigInt.zero;
      final updated = known?['document']?['updateTime'];
      final newerTime =
          updated is String &&
          (codec.decode({'timestampValue': updated}) as Timestamp).compareTo(
                clock,
              ) >
              0;
      if (newerTime ||
          known != null && versions[path] != null && current >= acknowledged) {
        updates[path] = known;
        continue;
      }
      updates[path] = versions[path] == null
          ? null
          : full[path] ?? _apply(known, op, clock, versions[path].toString());
    }
    void update(_View view) {
      final rows = {for (final row in view.rows) row['path'] as String: row};
      final query = view.request['query'] as Map<String, dynamic>?;
      for (final entry in updates.entries) {
        if (query == null && entry.key != view.request['path']) continue;
        if (query != null &&
            entry.key.substring(0, entry.key.lastIndexOf('/')) !=
                query['path']) {
          continue;
        }
        if (entry.value == null) {
          rows.remove(entry.key);
        } else {
          rows[entry.key] = entry.value!;
        }
      }
      view.rows = query == null
          ? rows.values.toList()
          : oracleLocalQuery(rows.values, query, codec);
    }

    for (final view in _views) {
      update(view);
    }
    for (final entry in _memory.values.toList()) {
      final request = Map<String, dynamic>.from(entry['request'] as Map);
      final view = _View(request)..rows = _rows(entry['rows']);
      update(view);
      _cache(request, view.rows);
    }
    for (final entry in updates.entries) {
      _cache({
        'kind': 'document',
        'path': entry.key,
      }, entry.value == null ? [] : [entry.value!]);
    }
  }

  Stream<OracleStoreSnapshot> watch(
    Map<String, dynamic> request, {
    bool cacheOnly = false,
  }) {
    final view = _View(request);
    late final StreamController<OracleStoreSnapshot> controller;
    StreamSubscription<void>? local;
    StreamSubscription<Map<String, dynamic>>? remote;
    Completer<void>? done;
    bool cancelled = false, waitingForNetwork = false;
    Timer? reconnect;
    var failures = 0;
    void emit() {
      if (!cancelled && isCurrent()) controller.add(_snapshot(view));
    }

    late final Future<void> Function() cancel;
    Future<void> run() async {
      _cancellations.add(cancel);
      try {
        await initialize();
        _guard();
        final cache = await _cached(request);
        if (cancelled) return;
        _views.add(view);
        if (cache != null) {
          view.rows = _rows(cache['rows']);
          view.ready = true;
        }
        local = _changes.stream.listen((_) {
          if (isCurrent()) emit();
          if (!isCurrent() ||
              !cacheOnly && (!networkEnabled || waitingForNetwork)) {
            reconnect?.cancel();
            reconnect = null;
            if (done != null && !done!.isCompleted) done!.complete();
          }
        });
        if (view.ready || cacheOnly || outbox.pending.isNotEmpty) emit();
        while (!cancelled && isCurrent()) {
          if (cacheOnly || !networkEnabled) {
            waitingForNetwork = true;
            done = Completer<void>();
            await done!.future;
            waitingForNetwork = false;
            continue;
          }
          done = Completer<void>();
          Object? streamError;
          remote = transport
              .watch({...request, 'delta': true})
              .listen(
                (packet) {
                  if (cancelled || !isCurrent()) return;
                  try {
                    if (request['kind'] == 'document') {
                      view.rows = packet['row'] == null
                          ? []
                          : [Map<String, dynamic>.from(packet['row'] as Map)];
                    } else if (packet['rows'] is List) {
                      view.rows = _rows(packet['rows']);
                    } else if (packet['patch'] is Map) {
                      final patch = packet['patch'] as Map,
                          rows = {
                            for (final row in view.rows)
                              row['path'] as String: row,
                          };
                      for (final path in patch['remove'] as List) {
                        rows.remove(path);
                      }
                      for (final row in _rows(patch['upserts'])) {
                        rows[row['path'] as String] = row;
                      }
                      view.rows = [
                        for (final path in patch['order'] as List)
                          if (rows[path] != null) rows[path]!,
                      ];
                    } else {
                      throw const FormatException('Sunucu akışı okunamadı.');
                    }
                    view.ready = true;
                    view.fromCache = false;
                    failures = 0;
                    _cache(request, view.rows);
                    emit();
                  } catch (error) {
                    streamError = error;
                    if (!done!.isCompleted) done!.complete();
                  }
                },
                onError: (Object error) {
                  streamError = error;
                  if (!done!.isCompleted) done!.complete();
                },
                onDone: () {
                  if (!done!.isCompleted) done!.complete();
                },
              );
          await done!.future;
          await remote?.cancel();
          remote = null;
          if (cancelled || !isCurrent()) break;
          if (streamError is OracleApiException &&
              [401, 403].contains((streamError as OracleApiException).status)) {
            view.rows = [];
            view.fromCache = true;
            _cache(request, []);
            emit();
            controller.addError(streamError!);
            break;
          }
          view.fromCache = true;
          if (view.ready) {
            emit();
          } else if (streamError != null) {
            controller.addError(streamError!);
          }
          failures++;
          final pause = Completer<void>();
          reconnect = Timer(
            Duration(seconds: failures.clamp(1, 5)),
            pause.complete,
          );
          done = pause;
          await pause.future;
          reconnect = null;
        }
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
      } finally {
        await remote?.cancel();
        await local?.cancel();
        _views.remove(view);
        _cancellations.remove(cancel);
        if (!controller.isClosed) await controller.close();
      }
    }

    cancel = () async {
      if (cancelled) return;
      cancelled = true;
      reconnect?.cancel();
      if (done != null && !done!.isCompleted) done!.complete();
      await remote?.cancel();
      await local?.cancel();
      _views.remove(view);
    };
    controller = StreamController<OracleStoreSnapshot>(
      onListen: () => unawaited(run()),
      onCancel: cancel,
    );
    return controller.stream;
  }

  Future<void> setNetwork(bool enabled) async {
    networkEnabled = enabled;
    outbox.enabled = enabled;
    if (enabled) outbox.resume();
    _notify();
  }

  Future<void> clearCache() async {
    if (_views.isNotEmpty || outbox.pending.isNotEmpty) {
      throw StateError('Etkin bağlantı varken önbellek temizlenemez.');
    }
    _cacheTimer?.cancel();
    _cacheTimer = null;
    await _cacheIo;
    _diskPending.clear();
    _memory.clear();
    final folder = Directory('${(await _directory()).path}/cache');
    await for (final entity in folder.list()) {
      if (entity is File) await entity.delete();
    }
  }

  Future<void> close() async {
    _closed = true;
    outbox.close();
    for (final cancel in _cancellations.toList()) {
      await cancel();
    }
    _cacheTimer?.cancel();
    await _cacheIo;
    await _flushCache();
    await _changes.close();
  }
}
