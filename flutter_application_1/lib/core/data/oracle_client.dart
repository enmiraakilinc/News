import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class OracleApiException implements Exception {
  final int status;
  final String code;
  OracleApiException(this.status, this.code);
  bool get canFallback =>
      status >= 500 || status == 429 || code == 'invalid-argument';
  @override
  String toString() => switch (code) {
    'permission-denied' => 'Bu alana erişim iznin yok.',
    'unauthenticated' => 'Oturumunu yenilemek için tekrar giriş yap.',
    _ => 'Bağlantı şu anda kurulamıyor. Biraz sonra tekrar dene.',
  };
}

/// Credentials stay in memory and never enter URLs. A brief circuit breaker
/// avoids making every media chunk wait when the migration host is unavailable.
class OracleDataClient {
  final http.Client _http;
  final Future<String?> Function() token;
  final Uri base;
  final Duration timeout;
  DateTime _retryAt = DateTime.fromMillisecondsSinceEpoch(0);
  OracleDataClient({
    required this.token,
    http.Client? client,
    Uri? base,
    this.timeout = const Duration(seconds: 5),
  }) : _http = client ?? http.Client(),
       base = base ?? Uri.parse('https://138.2.185.151') {
    if (this.base.scheme != 'https' ||
        this.base.userInfo.isNotEmpty ||
        this.base.query.isNotEmpty ||
        this.base.fragment.isNotEmpty) {
      throw ArgumentError('Sunucu bağlantısı HTTPS olmalı.');
    }
  }
  Future<Map<String, dynamic>> read(Map<String, dynamic> body) async {
    if (DateTime.now().isBefore(_retryAt)) {
      throw OracleApiException(503, 'unavailable');
    }
    final bearer = await token();
    late final http.Response response;
    try {
      response = await _http
          .post(
            base.resolve('/v1/read'),
            headers: {
              'Content-Type': 'application/json',
              if (bearer != null) 'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      _retryAt = DateTime.now().add(const Duration(seconds: 30));
      rethrow;
    } on http.ClientException {
      _retryAt = DateTime.now().add(const Duration(seconds: 30));
      rethrow;
    }
    if (response.statusCode >= 500 || response.statusCode == 429) {
      _retryAt = DateTime.now().add(const Duration(seconds: 30));
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw OracleApiException(
        response.statusCode,
        (data as Map?)?['error']?['code'] as String? ?? 'unavailable',
      );
    }
    if (data is! Map) throw const FormatException('Sunucu yanıtı okunamadı.');
    return Map<String, dynamic>.from(data);
  }

  void close() => _http.close();
}

bool oracleShouldFallback(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    error is FormatException ||
    error is UnsupportedError ||
    error is OracleApiException && error.canFallback;
