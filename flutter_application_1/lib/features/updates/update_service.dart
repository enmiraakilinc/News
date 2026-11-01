import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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

UpdateInfo? publicGithubUpdate(
  Map<String, dynamic> release, {
  required int currentCode,
}) {
  if (release['draft'] == true || release['prerelease'] == true) return null;
  final tag = release['tag_name'];
  if (tag is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
    return null;
  }
  final name = tag.substring(1);
  final notes = release['body'] as String? ?? '';
  final build = RegExp(
    r'Build code:\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(notes);
  final code = int.tryParse(build?.group(1) ?? '');
  if (code == null || code <= currentCode) return null;
  final assets = release['assets'];
  if (assets is! List) return null;
  for (final item in assets) {
    if (item is! Map ||
        item['name'] != 'Neural-Haber-$name-arm64.apk' ||
        item['browser_download_url'] is! String ||
        item['digest'] is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(item['digest'] as String)) {
      continue;
    }
    final url = item['browser_download_url'] as String;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.path !=
            '/enmiraakilinc/News/releases/download/$tag/Neural-Haber-$name-arm64.apk') {
      return null;
    }
    return UpdateInfo(
      code: code,
      name: name,
      url: url,
      notes: notes
          .replaceAll(RegExp(r'^Build code:\s*\d+\s*$', multiLine: true), '')
          .trim(),
      authenticated: false,
      sha256: (item['digest'] as String).substring('sha256:'.length),
    );
  }
  return null;
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
  static const _githubLatest =
      'https://api.github.com/repos/enmiraakilinc/News/releases/latest';

  static Future<UpdateInfo?> _checkGithub(int currentCode) async {
    final response = await http
        .get(
          Uri.parse(_githubLatest),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const UpdateCheckException(
        'GitHub sürüm bilgisi alınamadı. Biraz sonra tekrar dene.',
      );
    }
    final release = jsonDecode(response.body);
    if (release is! Map<String, dynamic>) return null;
    return publicGithubUpdate(release, currentCode: currentCode);
  }

  static Future<UpdateInfo?> _checkPrivate(int currentCode) async {
    await CoupleService.ensureReady().timeout(const Duration(seconds: 20));
    final endpoint = await WakeupService.endpoint();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (endpoint == null || token == null) return null;

    final uri = Uri.parse(
      endpoint,
    ).replace(path: '/updates/latest', query: null, fragment: null);
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final code = (decoded['code'] as num?)?.toInt() ?? 0;
    if (code <= currentCode) return null;

    String? abi;
    try {
      abi = await const MethodChannel(
        'app/permissions',
      ).invokeMethod<String>('abi').timeout(const Duration(seconds: 2));
    } catch (_) {}
    final url = updateUrlForAbi(decoded, abi);
    final download = Uri.tryParse(url);
    if (download == null) return null;
    final trustedPrivate =
        download.origin == uri.origin && download.path == '/updates/apk';
    final trustedPublic =
        download.scheme == 'https' &&
        download.host == 'github.com' &&
        RegExp(
          r'^/enmiraakilinc/News/releases/download/v\d+\.\d+\.\d+/Neural-Haber-\d+\.\d+\.\d+-arm64[.]apk$',
        ).hasMatch(download.path);
    if (!trustedPrivate && !trustedPublic) return null;

    final digest = decoded['sha256'] as String?;
    if (digest == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      return null;
    }
    return UpdateInfo(
      code: code,
      name: (decoded['name'] ?? '').toString(),
      url: url,
      notes: (decoded['notes'] ?? '').toString(),
      authenticated: trustedPrivate,
      sha256: digest,
    );
  }

  /// Yeni sürüm varsa bilgisini döndürür, yoksa null.
  static Future<UpdateInfo?> checkForUpdate({bool silent = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      try {
        final privateUpdate = await _checkPrivate(currentCode);
        if (privateUpdate != null) return privateUpdate;
      } catch (_) {
        // The public release is the fallback when the VPS or account session
        // cannot provide update metadata.
      }
      return await _checkGithub(currentCode);
    } catch (error) {
      if (silent) return null;
      if (error is UpdateCheckException) rethrow;
      throw const UpdateCheckException(
        'Güncelleme kontrol edilemedi. İnternet bağlantını kontrol edip tekrar dene.',
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
