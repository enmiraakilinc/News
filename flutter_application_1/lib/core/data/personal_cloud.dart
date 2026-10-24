import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart'
    show Blob, GetOptions, Source, Timestamp, FieldValue;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../features/pair/couple_service.dart';
import '../../features/media/chat_media.dart';
import 'oracle_media_batch.dart';
import 'oracle_personal_store.dart';

/// Account-only data. Sharing a couple secret or chat invite grants no access.
class PersonalCloud {
  static const enabled = bool.fromEnvironment('NEURAL_POSTGRES_PRIMARY');
  final String owner;
  PersonalCloud(this.owner, {DirectPersonalDb? store})
    : _db = store ?? DirectPersonalDb(owner);
  final DirectPersonalDb _db;
  DirectPersonalRef get _root => _db.doc('chatAccounts/$owner');
  void _guard() {
    _db.guard();
  }

  Future<String>? _secretFuture;
  Future<String> _secret() => _secretFuture ??= () async {
    _guard();
    final ref = _root.collection('personalConfig').doc('sync');
    final random = Random.secure();
    final candidate = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final value = await _db.runTransaction<String>((transaction) async {
      final current = await transaction.get(ref);
      if (current.exists) return current.data()!['secret'] as String;
      transaction.set(ref, {
        'secret': candidate,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return candidate;
    });
    _guard();
    return value;
  }();
  Future<Map<String, Map<String, dynamic>>> records(String kind) async {
    _guard();
    final result = await _root
        .collection('personalData')
        .where('kind', isEqualTo: kind)
        .get();
    final secret = await _secret();
    _guard();
    final values = <String, Map<String, dynamic>>{};
    for (final row in result.docs) {
      values[row.id] = Map<String, dynamic>.from(
        jsonDecode(
              CoupleService.decodePrivateText(
                row.data()!['cipher'] as String,
                secret,
              ),
            )
            as Map,
      );
    }
    final ordered = values.entries.toList()
      ..sort(
        (a, b) => ((a.value['_cloudOrder'] as num?) ?? 0).compareTo(
          (b.value['_cloudOrder'] as num?) ?? 0,
        ),
      );
    return Map.fromEntries(ordered);
  }

  Future<void> reconcile(
    String kind,
    Map<String, Map<String, dynamic>> before,
    Map<String, Map<String, dynamic>> after,
  ) async {
    _guard();
    final secret = await _secret();
    _guard();
    var batch = _db.batch(), count = 0;
    Future<void> flush() async {
      if (count > 0) {
        await batch.commit();
        _guard();
        batch = _db.batch();
        count = 0;
      }
    }

    for (final entry in after.entries) {
      if (jsonEncode(before[entry.key]) == jsonEncode(entry.value)) continue;
      final value = Map<String, dynamic>.from(entry.value);
      value['_cloudOrder'] ??=
          before[entry.key]?['_cloudOrder'] ??
          DateTime.now().microsecondsSinceEpoch;
      batch.set(_root.collection('personalData').doc(entry.key), {
        'kind': kind,
        'cipher': CoupleService.encodePrivateText(jsonEncode(value), secret),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (++count >= 100) await flush();
    }
    for (final id in before.keys.where((id) => !after.containsKey(id))) {
      batch.delete(_root.collection('personalData').doc(id));
      if (++count >= 100) await flush();
    }
    await flush();
  }

  DirectPersonalRef _file(String id) =>
      _root.collection('personalFiles').doc(id);
  Future<void> saveFile(String id, File file, {DateTime? expiresAt}) async {
    _guard();
    final size = await file.length();
    if (size < 1 || size > 100 * 1024 * 1024) {
      throw StateError('Dosya en fazla 100 MB olabilir.');
    }
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final ref = _file(id), existing = (await ref.get()).data();
    _guard();
    if (existing?['ready'] == true && existing?['sha256'] == digest) return;
    final count = (size / mediaChunkBytes).ceil();
    await ref.set({
      'size': size,
      'count': count,
      'ready': false,
      'sha256': digest,
      'createdAt': FieldValue.serverTimestamp(),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
    });
    final secret = await _secret(), input = await file.open();
    try {
      for (var start = 0; start < count; start += 4) {
        final batch = _db.batch();
        for (var i = start; i < min(start + 4, count); i++) {
          final bytes = await input.read(mediaChunkBytes);
          final transformed = await compute(transformMediaChunk, {
            'bytes': bytes,
            'secret': secret,
          });
          batch.set(ref.collection('chunks').doc('$i'), {
            'bytes': Blob(transformed['bytes'] as Uint8List),
            'iv': Blob(transformed['iv'] as Uint8List),
          });
        }
        _guard();
        await batch.commit();
      }
      await ref.update({'ready': true});
    } finally {
      await input.close();
    }
  }

  Future<bool> restoreFile(String id, File destination) async {
    _guard();
    final ref = _file(id),
        meta = (await ref.get(const GetOptions(source: Source.server))).data();
    _guard();
    if (meta == null) return false;
    final expiry = meta['expiresAt'] as Timestamp?;
    if (expiry != null && !expiry.toDate().isAfter(DateTime.now())) {
      throw StateError('Dosyanın erişim süresi doldu.');
    }
    final count = meta['count'] as int? ?? 0;
    if (meta['ready'] != true || count < 1 || count > 228) {
      throw StateError('Dosya henüz hazır değil.');
    }
    final secret = await _secret(),
        temporary = File('${destination.path}.download');
    final output = temporary.openWrite();
    try {
      for (var start = 0; start < count; start += 16) {
        final end = min(start + 16, count),
            paths = [
              for (var i = start; i < end; i++)
                ref.collection('chunks').doc('$i').path,
            ];
        final values = await readOracleMediaChunks(paths);
        for (var i = start; i < end; i++) {
          final data =
              values?[i - start] ??
              (await ref.collection('chunks').doc('$i').get()).data();
          if (data == null) {
            throw StateError('Dosyanın bir parçası bulunamadı.');
          }
          final transformed = await compute(transformMediaChunk, {
            'bytes': (data['bytes'] as Blob).bytes,
            'iv': (data['iv'] as Blob).bytes,
            'secret': secret,
            'decrypt': true,
          });
          output.add(transformed['bytes'] as Uint8List);
        }
      }
      await output.close();
      _guard();
      if (await temporary.length() != meta['size'] ||
          (await sha256.bind(temporary.openRead()).first).toString() !=
              meta['sha256']) {
        throw StateError('Dosya doğrulanamadı. Yeniden dene.');
      }
      await temporary.rename(destination.path);
      return true;
    } catch (_) {
      await output.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> removeFile(String id) async {
    _guard();
    final ref = _file(id), data = (await ref.get()).data();
    final count = (data?['count'] as int? ?? 0).clamp(0, 228),
        batch = _db.batch();
    for (var i = 0; i < count; i++) {
      batch.delete(ref.collection('chunks').doc('$i'));
    }
    batch.delete(ref);
    await batch.commit();
  }
}
