import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../../core/security/feature_access.dart';
import '../../core/security/microphone_session.dart';
import '../../core/utils/user_errors.dart';

class MicrophoneSessionScreen extends StatefulWidget {
  const MicrophoneSessionScreen({super.key});
  @override
  State<MicrophoneSessionScreen> createState() =>
      _MicrophoneSessionScreenState();
}

class _MicrophoneSessionScreenState extends State<MicrophoneSessionScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false, _active = false, _silenced = false, _checking = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final status = await MicrophoneSession.status();
      if (mounted) {
        setState(() {
          _active = status['mode'] == 'hold';
          _silenced = status['silenced'] == true;
        });
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_active) {
        await MicrophoneSession.stop('hold');
      } else {
        if (!MicrophoneSession.supported) {
          throw Exception(
            'Bu özellik yalnızca Android telefonda kullanılabilir.',
          );
        }
        await FeatureAccess.require('microphone');
        if (!mounted || !await MicrophoneSession.ensureDrawerHidden(context)) {
          return;
        }
        final permission = AudioRecorder();
        try {
          if (!await permission.hasPermission()) {
            throw Exception('Mikrofon izni gerekli.');
          }
        } finally {
          await permission.dispose();
        }
        if (!mounted) return;
        await MicrophoneSession.start('hold');
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback:
                    'Mikrofon oturumu açılamadı. Açık bir arama veya kayıt varsa durdurup yeniden dene.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Locking the screen never stops the native foreground service.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // User controls lifetime from this screen or the ongoing notification.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mikrofonu meşgul tut')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(_active ? Icons.mic : Icons.mic_none, size: 56),
        const SizedBox(height: 16),
        Text(
          _active ? 'Mikrofon oturumu açık' : 'Mikrofon oturumu kapalı',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const Text(
          'Başlattığında mikrofon kullanılır; ses dosyası oluşturulmaz ve ses gönderilmez. Ekran kilitliyken ve bu sayfadan çıkınca devam eder.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Android mikrofon göstergesi ve çalışan uygulamalar kaydı görünür. Bu kanalı telefon ayarından kapatırsan bildirim çekmecesinde görünmez. Pil tüketir. Başka uygulamalara erişimi engellemesi cihaza bağlıdır. Arama veya ses kaydı öncesinde bu oturumu durdur.',
        ),
        if (_silenced)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Android bu oturumun ses girişini susturdu. Başka uygulamaların engellendiğini varsayma.',
            ),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => MicrophoneSession.ensureDrawerHidden(context),
          child: const Text('Bildirim kanalı ayarı'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _toggle,
          icon: Icon(_active ? Icons.stop : Icons.mic),
          label: Text(
            _busy
                ? 'Bekle…'
                : _active
                ? 'Durdur'
                : 'Başlat',
          ),
        ),
      ],
    ),
  );
}
