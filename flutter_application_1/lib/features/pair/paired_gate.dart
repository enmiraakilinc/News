import 'package:flutter/material.dart';
import 'couple_service.dart';
import '../chat/letters_screen.dart';

/// İki cihaz gerektiren ekranları sarar. Eşleşme yoksa kullanıcıyı eşleşmeye
/// yönlendirir; varsa asıl içeriği [builder] ile gösterir.
class PairedGate extends StatefulWidget {
  final String title;
  final Widget Function(String coupleId, String secret) builder;
  const PairedGate({super.key, required this.title, required this.builder});

  @override
  State<PairedGate> createState() => _PairedGateState();
}

class _PairedGateState extends State<PairedGate> {
  bool _loading = true;
  String? _cid;
  String? _sec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cid = await CoupleService.coupleId();
    final sec = await CoupleService.secret();
    if (!mounted) return;
    setState(() {
      _cid = cid;
      _sec = sec;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cid == null || _sec == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("🔗", style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                const Text(
                  "Bu özellik için önce eşleşmen gerekiyor.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text("Eşleşmeye Git"),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LettersScreen()),
                    );
                    _load(); // dönünce eşleşme durumunu tazele
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.builder(_cid!, _sec!);
  }
}
