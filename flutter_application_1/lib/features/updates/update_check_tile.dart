import 'package:flutter/material.dart';
import 'update_service.dart';
import 'update_dialog.dart';

class UpdateCheckTile extends StatefulWidget {
  const UpdateCheckTile({super.key, this.check});
  final Future<UpdateInfo?> Function()? check;
  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  bool _busy = false;
  String _status = 'Yeni sürüm olup olmadığını kontrol et.';
  UpdateInfo? _available;

  Future<void> _check() async {
    if (_busy) return;
    if (_available != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => UpdateDialog(info: _available!),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final update =
          await (widget.check?.call() ??
              UpdateService.checkForUpdate(silent: false));
      if (!mounted) return;
      setState(() {
        _available = update;
        _status = update == null
            ? 'Uygulaman güncel.'
            : '${update.name} hazır. Güncellemek için dokun.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _status = error is UpdateCheckException
            ? error.message
            : 'Kontrol yapılamadı. Tekrar denemek için dokun.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.system_update_outlined),
    title: const Text('Güncellemeler'),
    subtitle: Text(_busy ? 'Güncelleme kontrol ediliyor…' : _status),
    trailing: _busy
        ? const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(_available == null ? Icons.refresh : Icons.download_outlined),
    onTap: _busy ? null : _check,
  );
}
