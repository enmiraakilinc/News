import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../pair/couple_service.dart';
import '../wakeup/wakeup_service.dart';

String updateUrlForAbi(Map<String, dynamic> data, String? abi) {
  final urls = data['urlsByAbi'];
  final candidate = urls is Map ? urls[abi] : null;
  if (candidate is String) {
    final uri = Uri.tryParse(candidate);
    if (uri?.scheme == 'https' && uri!.host.isNotEmpty) return candidate;
  }
  return (data['url'] ?? '').toString();
}

/// Yetkili hesabın özel sunucudan aldığı sürüm bilgisi.
/// APK adresi aynı sunucudadır; GitHub anahtarı telefona aktarılmaz.
class UpdateInfo {
  final int code;
  final String name;
  final String url;
  final String notes;
  final bool authenticated;
  final String? sha256;
  UpdateInfo({
    required this.code,
    required this.name,
    required this.url,
    required this.notes,
    this.authenticated = false,
    this.sha256,
  });
}

class UpdateService {
  /// Yeni sürüm varsa bilgisini döndürür, yoksa null.
  static Future<UpdateInfo?> checkForUpdate({bool silent = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final int currentCode = int.tryParse(info.buildNumber) ?? 0;

      await CoupleService.ensureReady().timeout(const Duration(seconds: 20));
      final endpoint = await WakeupService.endpoint();
      if (endpoint == null) {
        throw const UpdateCheckException(
          'Güncelleme sunucusuna şu anda ulaşılamıyor.',
        );
      }
      final uri = Uri.parse(
        endpoint,
      ).replace(path: '/updates/latest', query: null, fragment: null);
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        throw const UpdateCheckException(
          'Güncellemeyi kontrol etmek için tekrar giriş yap.',
        );
      }
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw UpdateCheckException(
          response.statusCode == 403
              ? 'Bu hesabın güncelleme erişimi doğrulanamadı.'
              : 'Güncelleme kontrol edilemedi. İnternet bağlantını kontrol edip tekrar dene.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final int code = (data['code'] as num?)?.toInt() ?? 0;
      String? abi;
      try {
        abi = await const MethodChannel(
          'app/permissions',
        ).invokeMethod<String>('abi').timeout(const Duration(seconds: 2));
      } catch (_) {}
      final String url = updateUrlForAbi(data, abi);
      if (code < 1) {
        throw const UpdateCheckException('Sürüm bilgisi okunamadı.');
      }
      if (code <= currentCode) return null;
      if (url.isEmpty) {
        throw const UpdateCheckException(
          'Güncelleme bağlantısı henüz hazır değil.',
        );
      }
      final download = Uri.parse(url);
      if (download.origin != uri.origin || download.path != '/updates/apk') {
        throw const UpdateCheckException(
          'Güncelleme bağlantısı doğrulanamadı.',
        );
      }
      final digest = data['sha256'] as String?;
      if (digest == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const UpdateCheckException('Güncelleme dosyası doğrulanamadı.');
      }

      return UpdateInfo(
        code: code,
        name: (data['name'] ?? '').toString(),
        url: url,
        notes: (data['notes'] ?? '').toString(),
        authenticated: true,
        sha256: digest,
      );
    } catch (error) {
      if (silent) return null;
      if (error is UpdateCheckException) rethrow;
      throw const UpdateCheckException(
        'Güncelleme kontrol edilemedi. Bağlantını kontrol edip tekrar dene.',
      );
    }
  }
}

class UpdateCheckException implements Exception {
  final String message;
  const UpdateCheckException(this.message);
  @override
  String toString() => message;
}
