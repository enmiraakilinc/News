import '../../core/data/oracle_media_batch.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import '../pair/couple_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class MediaPreview {
  final Uint8List bytes;
  final DateTime expiresAt;
  MediaPreview(this.bytes, this.expiresAt);
}

// Decode one fetched batch in one worker instead of starting a worker for
// every individual piece of a large video.
List<Uint8List> decodeMediaBatch(Map<String, dynamic> payload) => [
  for (final chunk in payload['chunks'] as List)
    if (payload['secret'] == null)
      (chunk as Map)['bytes'] as Uint8List
    else
      transformMediaChunk({
            ...Map<String, dynamic>.from(chunk as Map),
            'secret': payload['secret'],
            'decrypt': true,
          })['bytes']
          as Uint8List,
];

class MediaMemoryCache {
  final int maxBytes;
  final _items = <String, MediaPreview>{};
  int _bytes = 0;
  MediaMemoryCache({this.maxBytes = 24 * 1024 * 1024});
  MediaPreview? get(String key) {
    for (final id in _items.keys.toList()) {
      if (!_items[id]!.expiresAt.isAfter(DateTime.now())) remove(id);
    }
    final item = _items.remove(key);
    if (item != null) _items[key] = item;
    return item;
  }

  void remove(String key) {
    final item = _items.remove(key);
    if (item != null) _bytes -= item.bytes.length;
  }

  void put(String key, MediaPreview item) {
    remove(key);
    if (item.bytes.length > maxBytes ||
        !item.expiresAt.isAfter(DateTime.now())) {
      return;
    }
    while ((_bytes + item.bytes.length > maxBytes || _items.length >= 64) &&
        _items.isNotEmpty) {
      remove(_items.keys.first);
    }
    _items[key] = item;
    _bytes += item.bytes.length;
  }

  void clear() {
    _items.clear();
    _bytes = 0;
  }
}

const mediaPrefix = 'NEURAL_MEDIA:';
const maxChatMediaBytes = 20 * 1024 * 1024;
const maxChatVideoBytes = 100 * 1024 * 1024;
const maxChatFileBytes = 80 * 1024 * 1024;
int chatAttachmentLimit(String kind) => kind == 'video'
    ? maxChatVideoBytes
    : kind == 'file'
    ? maxChatFileBytes
    : maxChatMediaBytes;
const mediaChunkBytes = 450 * 1024;
const mediaTransferBatchSize = 8;
const chatMediaLifetime = Duration(days: 2);
const chatVideoLifetime = Duration(days: 2);
Duration chatAttachmentLifetime(String kind) =>
    kind == 'video' ? chatVideoLifetime : chatMediaLifetime;
bool chatAttachmentExpired(String kind, DateTime createdAt, DateTime now) =>
    !createdAt.add(chatAttachmentLifetime(kind)).isAfter(now);

/// Private-pair attachments retain secret-word encryption, outside message docs.
Map<String, dynamic> transformMediaChunk(Map<String, dynamic> input) {
  final bytes = input['bytes'] as Uint8List;
  final secret = input['secret'] as String?;
  if (secret == null) return {'bytes': bytes};
  final key = enc.Key(
    Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes),
  );
  final cipher = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  if (input['decrypt'] == true) {
    return {
      'bytes': Uint8List.fromList(
        cipher.decryptBytes(
          enc.Encrypted(bytes),
          iv: enc.IV(input['iv'] as Uint8List),
        ),
      ),
    };
  }
  final iv = enc.IV.fromSecureRandom(16);
  return {'bytes': cipher.encryptBytes(bytes, iv: iv).bytes, 'iv': iv.bytes};
}

class ChatMedia {
  static Future<String> accessScope() async {
    await CoupleService.ensureReady();
    return '${CoupleService.uid}:${sha256.convert(utf8.encode(await CoupleService.secret() ?? ''))}';
  }

  static CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('chatMedia');

  static Future<String> upload(
    Uint8List bytes,
    String name,
    String kind, {
    String? chatId,
    String? coupleId,
  }) async {
    if (!['file', 'photo', 'video', 'audio'].contains(kind) ||
        bytes.isEmpty ||
        bytes.length > chatAttachmentLimit(kind)) {
      throw Exception(
        'Dosya en fazla ${chatAttachmentLimit(kind) ~/ (1024 * 1024)} MB olabilir.',
      );
    }
    if ((chatId == null) == (coupleId == null)) {
      throw Exception('Sohbet bulunamadı.');
    }
    await CoupleService.ensureReady();
    final secret = coupleId == null ? null : await CoupleService.secret();
    if (coupleId != null &&
        (secret == null || await CoupleService.coupleId() != coupleId)) {
      throw Exception('Özel sohbet bağlantısı bulunamadı.');
    }
    final ref = _collection.doc();
    final chunks = (bytes.length / mediaChunkBytes).ceil();
    await ref.set({
      'owner': CoupleService.uid,
      'chatId': chatId,
      'coupleId': coupleId,
      'name': coupleId == null
          ? name.substring(0, name.length > 200 ? 200 : name.length)
          : 'Özel ek',
      'kind': kind,
      'size': bytes.length,
      'chunks': chunks,
      'createdAt': FieldValue.serverTimestamp(),
      'ready': false,
    });
    try {
      if (kind == 'photo') {
        final thumb = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 320,
          minHeight: 320,
          quality: 45,
          keepExif: false,
        );
        if (thumb.isNotEmpty && thumb.length <= 24576) {
          final encoded = secret == null
              ? <String, dynamic>{'bytes': thumb}
              : await compute(transformMediaChunk, {
                  'bytes': thumb,
                  'secret': secret,
                });
          await ref.collection('preview').doc('image').set({
            'bytes': Blob(encoded['bytes'] as Uint8List),
            if (encoded['iv'] != null) 'iv': Blob(encoded['iv'] as Uint8List),
          });
        }
      }
      // Small batches bound peak memory and keep retries reasonably sized.
      for (var start = 0; start < chunks; start += mediaTransferBatchSize) {
        final batch = FirebaseFirestore.instance.batch();
        for (
          var index = start;
          index < chunks && index < start + mediaTransferBatchSize;
          index++
        ) {
          final end = (index + 1) * mediaChunkBytes;
          final part = Uint8List.sublistView(
            bytes,
            index * mediaChunkBytes,
            end > bytes.length ? bytes.length : end,
          );
          final encoded = secret == null
              ? <String, dynamic>{'bytes': part}
              : await compute(transformMediaChunk, {
                  'bytes': part,
                  'secret': secret,
                });
          batch.set(ref.collection('chunks').doc('$index'), {
            'bytes': Blob(encoded['bytes'] as Uint8List),
            if (encoded['iv'] != null) 'iv': Blob(encoded['iv'] as Uint8List),
          });
        }
        await batch.commit();
      }
      await ref.update({'ready': true});
      return mediaPrefix +
          jsonEncode({'id': ref.id, 'name': name, 'kind': kind});
    } catch (_) {
      await remove(ref.id).catchError((_) {});
      rethrow;
    }
  }

  static String idFrom(String text) {
    final id = (jsonDecode(text.substring(mediaPrefix.length)) as Map)['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(id)) {
      throw Exception('Geçersiz dosya.');
    }
    return id;
  }

  static Future<Uint8List> download(
    String id, {
    void Function(double)? onProgress,
  }) async {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    final secret = await CoupleService.secret();
    final scope = '$uid:${sha256.convert(utf8.encode(secret ?? ''))}';
    if (_cacheScope != scope) {
      _cache.clear();
      _cacheScope = scope;
    }
    final key = '$scope/$id';
    final cached = _cache.get(key);
    if (cached != null) {
      await checkAccess(id);
      if (CoupleService.uid != uid) {
        throw Exception('Hesabın değişti. Yeniden aç.');
      }
      onProgress?.call(1);
      return cached.bytes;
    }
    final future = _pending.putIfAbsent(
      key,
      () => _download(id, onProgress: onProgress),
    );
    try {
      final result = await future;
      if (CoupleService.uid != uid || await CoupleService.secret() != secret) {
        throw Exception('Sohbet bağlantısı değişti. Yeniden aç.');
      }
      _cache.put(key, result);
      return result.bytes;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  static final _cache = MediaMemoryCache();
  static final _pending = <String, Future<MediaPreview>>{};
  static String? _cacheScope;
  static void clearCache() {
    _cache.clear();
    _cacheScope = null;
  }

  static Future<MediaPreview> _download(
    String id, {
    void Function(double)? onProgress,
  }) async {
    await CoupleService.ensureReady();
    final ref = _collection.doc(id);
    final data =
        (await ref
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 30)))
            .data();
    if (data == null ||
        data['ready'] != true ||
        chatAttachmentExpired(
          data['kind'] as String,
          (data['createdAt'] as Timestamp).toDate(),
          DateTime.now(),
        )) {
      throw Exception('Dosyanın erişim süresi dolmuş.');
    }
    final size = data['size'] as int;
    final count = data['chunks'] as int;
    if (size < 1 ||
        size > chatAttachmentLimit(data['kind'] as String) ||
        count != (size / mediaChunkBytes).ceil()) {
      throw Exception('Geçersiz dosya boyutu.');
    }
    final cid = data['coupleId'] as String?;
    final secret = cid == null ? null : await CoupleService.secret();
    if (cid != null &&
        (await CoupleService.coupleId() != cid || secret == null)) {
      throw Exception('Gizli kelimeyle bağlantı gerekli.');
    }
    final builder = BytesBuilder(copy: false);
    // Fetch only on explicit tap, never as part of the message listener.
    for (var start = 0; start < count; start += 16) {
      final ids = [for (var i = start; i < count && i < start + 16; i++) '$i'];
      final batch = await readOracleMediaChunks([
        for (final id in ids) ref.collection('chunks').doc(id).path,
      ]);
      late final Map<String, Map<String, dynamic>?> docs;
      if (batch != null) {
        docs = {for (var i = 0; i < ids.length; i++) ids[i]: batch[i]};
      } else {
        final snapshots = await Future.wait([
          for (final id in ids)
            ref
                .collection('chunks')
                .doc(id)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 30)),
        ]);
        docs = {for (final doc in snapshots) doc.id: doc.data()};
      }
      final encoded = <Map<String, dynamic>>[];
      for (final id in ids) {
        final chunk = docs[id];
        if (chunk == null) throw Exception('Dosya eksik.');
        encoded.add({
          'bytes': (chunk['bytes'] as Blob).bytes,
          'iv': (chunk['iv'] as Blob?)?.bytes,
        });
      }
      final decoded = secret == null
          ? decodeMediaBatch({'chunks': encoded, 'secret': null})
          : await compute(decodeMediaBatch, {
              'chunks': encoded,
              'secret': secret,
            });
      for (final bytes in decoded) {
        builder.add(bytes);
        if (builder.length > size) throw Exception('Geçersiz dosya.');
      }
      onProgress?.call(builder.length / size);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != size) throw Exception('Dosya eksik.');
    return MediaPreview(
      bytes,
      (data['createdAt'] as Timestamp).toDate().add(chatMediaLifetime),
    );
  }

  static Future<MediaPreview?> preview(String id) async {
    await CoupleService.ensureReady();
    final ref = _collection.doc(id);
    final data = (await ref.get(
      const GetOptions(source: Source.server),
    )).data();
    if (data == null || data['ready'] != true || data['kind'] != 'photo') {
      return null;
    }
    final expires = (data['createdAt'] as Timestamp).toDate().add(
      chatMediaLifetime,
    );
    if (!expires.isAfter(DateTime.now())) return null;
    final cid = data['coupleId'] as String?;
    final secret = cid == null ? null : await CoupleService.secret();
    if (cid != null &&
        (await CoupleService.coupleId() != cid || secret == null)) {
      return null;
    }
    final uid = CoupleService.uid;
    final key = '$uid:${sha256.convert(utf8.encode(secret ?? ''))}:preview/$id';
    final cached = _cache.get(key);
    if (cached != null) return cached;
    final thumbnail =
        (await ref
                .collection('preview')
                .doc('image')
                .get(const GetOptions(source: Source.server)))
            .data();
    if (thumbnail == null) return null;
    final decoded = await compute(transformMediaChunk, {
      'bytes': (thumbnail['bytes'] as Blob).bytes,
      'secret': secret,
      'decrypt': true,
      'iv': (thumbnail['iv'] as Blob?)?.bytes,
    });
    if (uid != CoupleService.uid ||
        (cid != null && await CoupleService.secret() != secret)) {
      return null;
    }
    final result = MediaPreview(decoded['bytes'] as Uint8List, expires);
    _cache.put(key, result);
    return result;
  }

  static Future<void> checkAccess(String id) async {
    await CoupleService.ensureReady();
    final data =
        (await _collection
                .doc(id)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 30)))
            .data();
    if (data == null ||
        data['ready'] != true ||
        chatAttachmentExpired(
          data['kind'] as String,
          (data['createdAt'] as Timestamp).toDate(),
          DateTime.now(),
        )) {
      throw Exception('Dosyanın erişim süresi dolmuş.');
    }
    final cid = data['coupleId'] as String?;
    if (cid != null &&
        (await CoupleService.coupleId() != cid ||
            await CoupleService.secret() == null)) {
      throw Exception('Gizli kelimeyle bağlantı gerekli.');
    }
    final chat = await FirebaseFirestore.instance
        .collection(cid == null ? 'chats' : 'couples')
        .doc(cid ?? data['chatId'] as String)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 30));
    if (!List<String>.from(
      chat.data()?['members'] ?? [],
    ).contains(CoupleService.uid)) {
      throw Exception('Bu sohbete erişilemiyor.');
    }
  }

  static Future<void> remove(String id, {bool explicitly = false}) async {
    final ref = _collection.doc(id);
    final data = (await ref.get(
      const GetOptions(source: Source.server),
    )).data();
    if (data == null) return;
    if (explicitly &&
        data['kind'] == 'video' &&
        data['owner'] == CoupleService.uid) {
      await ref.update({'deleteRequestedAt': FieldValue.serverTimestamp()});
    }
    final count = data['chunks'] as int;
    if (count < 1 || count > (maxChatVideoBytes / mediaChunkBytes).ceil()) {
      throw Exception(
        'Dosyanın parça bilgileri geçersiz. Yeniden göndermeyi dene.',
      );
    }
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(ref.collection('preview').doc('image'));
    for (var i = 0; i < count; i++) {
      batch.delete(ref.collection('chunks').doc('$i'));
    }
    batch.delete(ref);
    await batch.commit();
  }

  static Future<void> cleanupExpired() async {
    await CoupleService.ensureReady();
    final db = FirebaseFirestore.instance;
    final conversations = await db
        .collection('chats')
        .where('members', arrayContains: CoupleService.uid)
        .get();
    final queries = <Query<Map<String, dynamic>>>[
      _collection.where('owner', isEqualTo: CoupleService.uid),
      for (final chat in conversations.docs)
        _collection.where('chatId', isEqualTo: chat.id),
    ];
    final cid = await CoupleService.coupleId();
    if (cid != null) queries.add(_collection.where('coupleId', isEqualTo: cid));
    final cutoff = DateTime.now().subtract(chatMediaLifetime);
    // Consent records contain no media bytes and share the attachment retention.
    for (final role in ['ownerUid', 'requesterUid']) {
      try {
        final requests = await db
            .collection('mediaDownloadRequests')
            .where(role, isEqualTo: CoupleService.uid)
            .get();
        for (final request in requests.docs) {
          final date = request.data()['expiresAt'];
          if (date is Timestamp && !date.toDate().isAfter(DateTime.now())) {
            await request.reference.delete();
          }
        }
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
      }
    }
    final ids = <String>{};
    for (final query in queries) {
      // Metadata only; no video bytes downloaded during cleanup.
      for (final doc in (await query.get()).docs) {
        final created = doc.data()['createdAt'];
        if (created is Timestamp &&
            chatAttachmentExpired(
              doc.data()['kind'] as String,
              created.toDate(),
              DateTime.now(),
            )) {
          ids.add(doc.id);
        }
      }
    }
    for (final id in ids) {
      try {
        await remove(id);
      } on FirebaseException catch (error) {
        // Older clients and a changed retention policy must not stop other cleanup.
        if (error.code != 'permission-denied' && error.code != 'not-found') {
          rethrow;
        }
      }
    }
    final folder = await getTemporaryDirectory();
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('neural_media_')) {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    }
  }
}
