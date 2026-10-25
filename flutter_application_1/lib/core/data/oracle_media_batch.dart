import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_firestore_bridge.dart';
import 'oracle_client.dart';
import 'dart:typed_data';

List<Map<String, dynamic>> decodeBinaryMedia(Uint8List bytes, int count) {
  if (count < 1 || count > 16) {
    throw const FormatException('Geçersiz medya paket sayısı.');
  }
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 6 ||
      String.fromCharCodes(bytes.take(4)) != 'NMC1' ||
      data.getUint16(4) != count) {
    throw const FormatException('Medya paketi okunamadı.');
  }
  var offset = 6;
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    if (offset + 5 > bytes.length) {
      throw const FormatException('Eksik medya paketi.');
    }
    final size = data.getUint32(offset), iv = bytes[offset + 4];
    offset += 5;
    if (size < 1 ||
        size > 460816 ||
        ![0, 16].contains(iv) ||
        offset + iv + size > bytes.length) {
      throw const FormatException('Geçersiz medya parçası.');
    }
    final item = <String, dynamic>{};
    if (iv > 0) {
      item['iv'] = Blob(Uint8List.sublistView(bytes, offset, offset + iv));
    }
    offset += iv;
    item['bytes'] = Blob(Uint8List.sublistView(bytes, offset, offset + size));
    offset += size;
    result.add(item);
  }
  if (offset != bytes.length) {
    throw const FormatException('Fazladan medya verisi.');
  }
  return result;
}

/// Bounded batches keep a large attachment from starting a request per piece.
Future<List<Map<String, dynamic>>?> readOracleMediaChunks(
  List<String> paths,
) async {
  final platform = FirebaseFirestorePlatform.instance;
  if (platform is! OracleFirestoreBridge || platform.preferNative) return null;
  if (platform.primary) {
    final uid = platform.store.uid;
    try {
      final bytes = await platform.primaryTransport.mediaBytes(paths);
      if (platform.store.uid != uid) {
        throw OracleApiException(401, 'unauthenticated');
      }
      return decodeBinaryMedia(bytes, paths.length);
    } on OracleApiException catch (error) {
      // Compatibility only with a server which predates the binary endpoint.
      if (error.status != 404) rethrow;
    }
  }
  try {
    final request = <String, dynamic>{'kind': 'documents', 'paths': paths};
    final uid = platform.primary ? platform.store.uid : null;
    final response = platform.primary
        ? await platform.primaryTransport.post('/v1/read', request)
        : await platform.client.read(
            request,
            requestTimeout: const Duration(seconds: 30),
          );
    if (platform.primary && platform.store.uid != uid) {
      throw OracleApiException(401, 'unauthenticated');
    }
    final rows = {
      for (final row in response['rows'] as List)
        (row as Map)['path'] as String: row,
    };
    if (paths.any((p) => !rows.containsKey(p))) return null;
    return [
      for (final path in paths)
        platform.codec.fields(rows[path]!['document']['fields'] as Map),
    ];
  } catch (error) {
    if (!oracleShouldFallback(error)) rethrow;
    return null;
  }
}
