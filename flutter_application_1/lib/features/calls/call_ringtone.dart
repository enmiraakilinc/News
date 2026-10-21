import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CallRingtone {
  static const channel = MethodChannel('app/call_ringtone');
  static Future<void> ring(String id) =>
      channel.invokeMethod<void>('ring', {'id': id});
  static Future<void> stop([String? id]) =>
      channel.invokeMethod<void>('stop', {'id': ?id});
}

class CallRingtoneSettings extends StatefulWidget {
  const CallRingtoneSettings({super.key});
  @override
  State<CallRingtoneSettings> createState() => _CallRingtoneSettingsState();
}

class _CallRingtoneSettingsState extends State<CallRingtoneSettings>
    with WidgetsBindingObserver {
  String _mode = 'sound', _name = 'Telefonun varsayılan zil sesi';
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _change('get');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallRingtone.stop('preview').catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      CallRingtone.stop('preview').catchError((_) {});
    }
  }

  Future<void> _change(String method, [String? mode]) async {
    setState(() => _busy = true);
    try {
      final data = await CallRingtone.channel.invokeMapMethod<String, dynamic>(
        method,
        {'mode': ?mode},
      );
      if (mounted && data != null) {
        setState(() {
          _mode = data['mode'] as String? ?? 'sound';
          _name = data['name'] as String? ?? 'Telefonun varsayılan zil sesi';
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ses ayarı açılamadı. Yerel bir ses dosyasıyla yeniden dene.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.ring_volume),
    title: const Text('Arama zil sesi ve titreşim'),
    subtitle: Text(
      '${const {'sound': 'Sesli', 'vibrate': 'Titreşim', 'silent': 'Sessiz'}[_mode]} · $_name',
    ),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'Sesli ve görüntülü gelen aramalar için bu telefonun ayarıdır. '
          'Telefonun sessiz modu, Rahatsız Etmeyin ve bildirim kanalı ayarları korunur. Alarm sesini değiştirmez.',
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          initialValue: _mode,
          key: ValueKey(_mode),
          decoration: const InputDecoration(labelText: 'Çalma biçimi'),
          items: const [
            DropdownMenuItem(value: 'sound', child: Text('Sesli ve titreşim')),
            DropdownMenuItem(
              value: 'vibrate',
              child: Text('Yalnızca titreşim'),
            ),
            DropdownMenuItem(value: 'silent', child: Text('Sessiz')),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) _change('setMode', value);
                },
        ),
      ),
      ListTile(
        title: const Text('Telefonun zil seslerinden seç'),
        subtitle: Text(_name),
        leading: const Icon(Icons.music_note),
        onTap: _busy ? null : () => _change('pickSystem'),
      ),
      ListTile(
        title: const Text('Kendi ses dosyamı seç'),
        subtitle: const Text(
          'İndirdiğin ses dosyası · en fazla 10 MB. Dosyayı cihazından silme; ses sunucuya yüklenmez.',
        ),
        leading: const Icon(Icons.audio_file_outlined),
        onTap: _busy ? null : () => _change('pickFile'),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('5 saniye dene'),
            onPressed: _busy ? null : () => _change('preview'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _change('stop'),
            child: const Text('Durdur'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _change('default'),
            child: const Text('Varsayılana dön'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _change('channelSettings'),
            child: const Text('Telefon bildirim ayarı'),
          ),
        ],
      ),
    ],
  );
}
