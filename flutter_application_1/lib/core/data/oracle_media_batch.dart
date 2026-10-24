import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'oracle_firestore_bridge.dart';
import 'oracle_client.dart';

/// Bounded batches keep a large attachment from starting a request per piece.
Future<List<Map<String, dynamic>>?> readOracleMediaChunks(
  List<String> paths,
) async {
  final platform = FirebaseFirestorePlatform.instance;
  if (platform is! OracleFirestoreBridge || platform.preferNative) return null;
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
