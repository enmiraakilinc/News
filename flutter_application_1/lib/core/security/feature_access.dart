import 'package:flutter/material.dart';
import 'microphone_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local usage switches, separate from Android's permission grants.
class FeatureAccess {
  static const labels = {
    'camera': 'Kamera',
    'microphone': 'Mikrofon',
    'location': 'Konum',
    'calls': 'Sesli aramalar',
  };
  static Future<bool> enabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool('feature_access_$key') ?? true;
  }

  static Future<void> require(String key) async {
    if (!await enabled(key)) {
      throw Exception(
        '${labels[key]} kullanımı kapalı. Ayarlar > İzinler bölümünden açabilirsin.',
      );
    }
  }
}

class FeatureAccessSwitches extends StatefulWidget {
  const FeatureAccessSwitches({super.key});
  @override
  State<FeatureAccessSwitches> createState() => _FeatureAccessSwitchesState();
}

class _FeatureAccessSwitchesState extends State<FeatureAccessSwitches> {
  final Map<String, bool> _values = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final key in FeatureAccess.labels.keys) {
      final enabled = await FeatureAccess.enabled(key);
      if (mounted) setState(() => _values[key] = enabled);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Bu anahtarlar uygulama içindeki kullanımı durdurur; sistem izinlerini gizlemez veya değiştirmez. Android iznini kaldırmak için telefon ayarlarını aç.',
        ),
      ),
      for (final entry in FeatureAccess.labels.entries)
        SwitchListTile(
          title: Text(entry.value),
          subtitle: const Text(
            'Yalnızca sen ilgili işlemi başlattığında kullanılır.',
          ),
          value: _values[entry.key] ?? false,
          onChanged: !_values.containsKey(entry.key)
              ? null
              : (value) async {
                  await (await SharedPreferences.getInstance()).setBool(
                    'feature_access_${entry.key}',
                    value,
                  );
                  if (entry.key == 'microphone' && !value) {
                    await MicrophoneSession.requestStop();
                  }
                  if (mounted) setState(() => _values[entry.key] = value);
                },
        ),
    ],
  );
}
