// APK indirme ve kurma penceresidir. Geri almada uyarıyı da gösterir.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'update_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  int _receivedMB = 0;
  int _totalMB = 0;
  String? _errorText;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _receivedMB = 0;
      _totalMB = 0;
      _errorText = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.info.name.isEmpty ? 'guncelleme' : widget.info.name;
      final file = File('${dir.path}/neural-haber-$safe.apk');

      final request = http.Request('GET', Uri.parse(widget.info.url));
      if (widget.info.authenticated) {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token == null) {
          throw Exception('Güncelleme için yeniden giriş yap.');
        }
        request.headers['Authorization'] = 'Bearer $token';
        request.followRedirects = false;
      }
      final client = http.Client();
      try {
        final resp = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw Exception('İndirme başarısız (kod ${resp.statusCode}).');
        }
        final total = resp.contentLength ?? 0;
        int received = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in resp.stream.timeout(
            const Duration(seconds: 45),
          )) {
            sink.add(chunk);
            received += chunk.length;
            if (mounted) {
              setState(() {
                _receivedMB = received ~/ (1024 * 1024);
                _totalMB = total ~/ (1024 * 1024);
                _progress = total > 0 ? received / total : 0;
              });
            }
          }
        } finally {
          await sink.close();
        }
        if (widget.info.sha256 != null &&
            (await sha256.bind(file.openRead()).first).toString() !=
                widget.info.sha256) {
          await file.delete();
          throw Exception('Güncelleme dosyası doğrulanamadı. Yeniden dene.');
        }
      } finally {
        client.close();
      }

      final res = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type != ResultType.done) {
        throw Exception('Kurulum açılamadı. ${res.message}');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _errorText = 'Güncelleme inemedi: ${e.toString().replaceFirst("Exception: ", "")}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_downloading,
      child: Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.outlineVariant, width: 1.5),
                ),
                child: Icon(
                  Icons.rocket_launch,
                  color: colors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                info.rollback
                    ? 'Kararlı sürüme geri dönmeniz gerekiyor'
                    : info.name.isEmpty
                    ? 'Yeni sürüm mevcut'
                    : 'Yeni sürüm ${info.name}',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'Güncellemeye hazır 🎉',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (info.notes.trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildNotes(info.notes),
                  ),
                ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 8,
                    backgroundColor: colors.outlineVariant,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _progress > 0
                      ? 'İndiriliyor… %${(_progress * 100).toStringAsFixed(0)}'
                            '${_totalMB > 0 ? "  ($_receivedMB/$_totalMB MB)" : ""}'
                      : 'İndiriliyor…',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Sonra'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _download,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Güncelle'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNotes(String notes) {
    final colors = Theme.of(context).colorScheme;
    final lines = notes.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.map((line) {
      final t = line.trim();
      if (t.startsWith('•') || t.startsWith('-')) {
        final txt = t.substring(1).trim();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 15,
                  color: colors.primary,
                ),
              ),
              Expanded(
                child: Text(
                  txt,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: colors.onSurface,
          ),
        ),
      );
    }).toList();
  }
}
