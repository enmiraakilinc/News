import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/notifications/incoming_call_settings.dart';
import '../storage/storage_monitor.dart';
import '../../core/security/feature_access.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ayarlar')),
    body: ListView(
      children: [
        const NotificationsPanel(),
        const StorageStatusCard(),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('İzinler'),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const AppPermissionsScreen()),
          ),
        ),
      ],
    ),
  );
}

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({super.key});
  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('app/permissions');
  Map<String, dynamic>? _status;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (mounted) setState(() => _status = status);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('İzinler')),
    body: ListView(
      children: [
        const FeatureAccessSwitches(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'İzinler yalnızca ilgili özelliği kullandığında istenir. Burada izin verilmesi kayıt veya paylaşım başlatmaz.',
          ),
        ),
        for (final entry in const [
          ('camera', 'Kamera', 'Fotoğraf ve video çekmek için.'),
          (
            'microphone',
            'Mikrofon',
            'Sesli not kaydı ve kabul ettiğin sesli aramalar için.',
          ),
          (
            'notifications',
            'Bildirimler',
            'Açtığın sohbet bildirimleri ve izin verdiğin uyandırma isteği için.',
          ),
          (
            'location',
            'Konum',
            'Sohbette sen konum paylaşmayı seçtiğinde; arka planda takip yapılmaz.',
          ),
        ])
          ListTile(
            title: Text('Sistem izni: ${entry.$2}'),
            subtitle: Text(entry.$3),
            trailing: Text(
              _status == null
                  ? '—'
                  : _status![entry.$1] == true
                  ? 'İzinli'
                  : 'İzin yok',
            ),
          ),
        const ListTile(
          title: Text('Fotoğraf seçimi'),
          subtitle: Text(
            'Sistem seçicisinden yalnızca seçtiğin fotoğraflar alınır. Galerinin tümü taranmaz.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: () async {
              try {
                await _channel.invokeMethod('settings');
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Telefon ayarlarından uygulamanın izinlerini açabilirsin.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Telefonun uygulama ayarlarını aç'),
          ),
        ),
      ],
    ),
  );
}
