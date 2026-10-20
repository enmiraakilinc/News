import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_account.dart';
import '../pair/couple_service.dart';

class ChatAccountScreen extends StatefulWidget {
  const ChatAccountScreen({super.key});
  @override
  State<ChatAccountScreen> createState() => _ChatAccountScreenState();
}

class _ChatAccountScreenState extends State<ChatAccountScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _oldPassword = TextEditingController();
  String? _linkedCode;
  String? _error;
  bool _busy = true;
  bool _login = false;
  bool _change = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await CoupleService.ensureReady();
      String? code = ChatAccount.currentCode;
      try {
        code = await ChatAccount.shortCode() ?? code;
      } catch (_) {
        /* Old code stays usable offline or before server publication. */
      }
      if (mounted) setState(() => _linkedCode = code);
    } catch (e) {
      if (mounted) setState(() => _error = ChatAccount.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [_code, _password, _confirmation, _oldPassword]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_login && _password.text != _confirmation.text) {
      setState(() => _error = 'Şifreler aynı olmalı.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_login) {
        await ChatAccount.signIn(_code.text, _password.text);
        if (mounted) Navigator.pop(context);
      } else if (_change) {
        await ChatAccount.changePassword(_oldPassword.text, _password.text);
        if (mounted) {
          setState(() => _change = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Şifren değiştirildi.')));
        }
      } else {
        final code = await ChatAccount.protect(_password.text);
        if (mounted) setState(() => _linkedCode = code);
      }
      _password.clear();
      _confirmation.clear();
      _oldPassword.clear();
    } catch (e) {
      if (mounted) setState(() => _error = ChatAccount.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _secret(TextEditingController controller, String label) => TextField(
    controller: controller,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    enabled: !_busy,
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kişisel sohbet hesabı')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Kişilerin ve mesajların telefonunda ve emülatörde aynı hesapla açılır. Ortak alanın gizli kelimesi ayrıdır.',
          ),
          const SizedBox(height: 20),
          if (_linkedCode != null && !_login && !_change) ...[
            const Text(
              'Kişisel hesap kodun',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(_linkedCode!),
            if (ChatAccount.currentCode != _linkedCode)
              const Text(
                'Eski uzun kodun da geçerlidir. Şifren ve sohbetlerin değişmez.',
              ),
            if (ChatAccount.currentCode != _linkedCode &&
                ChatAccount.currentCode != null)
              ExpansionTile(
                title: const Text('Eski kod (yedek)'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(ChatAccount.currentCode!),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _linkedCode!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hesap kodu kopyalandı.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Kodu kopyala'),
            ),
            const Text(
              'Diğer cihazda “Mevcut hesabıma giriş yap” seçeneğine bu kodu ve şifreni gir. Kodunu sakla; e-posta ile şifre kurtarma yok.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : () => setState(() => _change = true),
              child: const Text('Şifremi değiştir'),
            ),
          ] else ...[
            if (_login) ...[
              TextField(
                controller: _code,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Kişisel hesap kodu',
                ),
              ),
              const Text(
                'Bu cihazdaki sohbetler diğer hesapla birleştirilmez. Ortak alanı açmak için gizli kelimeni yeniden girmen gerekebilir.',
              ),
            ] else if (_change)
              _secret(_oldPassword, 'Mevcut şifre')
            else
              const Text(
                'Bunu önce kişilerinin bulunduğu telefonda yap. Mevcut sohbetlerin korunur. Kodunu ve şifreni sakla; e-posta ile şifre kurtarma yok.',
              ),
            _secret(
              _password,
              _login ? 'Şifre' : 'Yeni şifre (en az 8 karakter)',
            ),
            if (!_login) _secret(_confirmation, 'Şifreyi tekrar yaz'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _login
                    ? 'Giriş yap'
                    : _change
                    ? 'Şifreyi değiştir'
                    : 'Mevcut sohbetlerimi hesabıma bağla',
              ),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_busy)
            TextButton(
              onPressed: () => setState(() {
                _login = !_login;
                _change = false;
                _error = null;
                _password.clear();
                _confirmation.clear();
                _oldPassword.clear();
              }),
              child: Text(
                _login
                    ? 'Bu cihazdaki hesabıma dön'
                    : 'Mevcut hesabıma giriş yap',
              ),
            ),
        ],
      ),
    ),
  );
}
