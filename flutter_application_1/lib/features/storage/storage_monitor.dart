import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';

class StorageMonitor {
  static final warning = ValueNotifier<bool>(false);
  static Future<Map<String, dynamic>?> check() async {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    const endpoint = 'https://138.2.185.151';
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) return null;
    final response = await http
        .get(
          Uri.parse('$endpoint/storage/status'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || CoupleService.uid != uid) return null;
    final report = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (report['bytes'] is! num ||
        report['limitBytes'] is! num ||
        report['checkedAt'] is! String) {
      return null;
    }
    await (await SharedPreferences.getInstance()).setString(
      'storage_last_report_oracle',
      jsonEncode(report),
    );
    warning.value = report['warning'] == true;
    return report;
  }
}

class StorageStatusCard extends StatefulWidget {
  const StorageStatusCard({super.key});
  @override
  State<StorageStatusCard> createState() => _StorageStatusCardState();
}

class _StorageStatusCardState extends State<StorageStatusCard> {
  Map<String, dynamic>? _report;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        'storage_last_report_oracle',
      );
      if (raw != null && mounted) {
        setState(
          () => _report = {
            ...Map<String, dynamic>.from(jsonDecode(raw) as Map),
            'stale': true,
          },
        );
      }
      final report = await StorageMonitor.check();
      if (report != null && mounted) setState(() => _report = report);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = (_report?['bytes'] as num?)?.toDouble();
    final limit = (_report?['limitBytes'] as num?)?.toDouble();
    final warning = _report?['warning'] == true;
    final observed = DateTime.tryParse(
      _report?['observedAt'] as String? ?? '',
    )?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sunucu depolaması',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Depolamayı kontrol et',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (bytes != null && limit != null && limit > 0) ...[
              Text(
                '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(limit / 1024 / 1024).toStringAsFixed(0)} MB · %${(bytes / limit * 100).toStringAsFixed(1)}',
              ),
              LinearProgressIndicator(
                value: (bytes / limit).clamp(0, 1),
                color: warning ? Theme.of(context).colorScheme.error : null,
              ),
              if (warning)
                const Text(
                  'Sunucu diski dolmaya yaklaşıyor. Süresi dolan dosyaların temizliğini kontrol et.',
                ),
              if (observed != null)
                Text(
                  'Son ölçüm: ${observed.day}.${observed.month}.${observed.year} ${observed.hour.toString().padLeft(2, '0')}:${observed.minute.toString().padLeft(2, '0')}',
                ),
              if (_report?['stale'] == true)
                const Text(
                  'Güncel ölçüm alınamadı; son başarılı kayıt gösteriliyor.',
                ),
            ] else
              Text(
                _busy
                    ? 'Ölçüm alınıyor…'
                    : 'Depolama ölçümü şu anda alınamadı.',
              ),
            const Text(
              'Sunucunun uygulama bölümündeki toplam disk kullanımıdır; sistem ve yedekler de dahildir. %80 dolulukta uyarı gösterilir. Ekran açılınca güncellenir.',
            ),
          ],
        ),
      ),
    );
  }
}
