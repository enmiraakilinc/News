import 'dart:async';
import '../../core/widgets/date_input.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CounterPage extends StatefulWidget {
  final Future<void> Function() onChanged;
  const CounterPage({super.key, required this.onChanged});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  DateTime? _start;
  String _title = 'Gün sayacım';
  bool _ready = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _start = DateTime.tryParse(p.getString('counter_start') ?? '');
      _title = p.getString('counter_title') ?? 'Gün sayacım';
      _ready = true;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    if (_start != null) {
      await p.setString('counter_start', _start!.toIso8601String());
    }
    await p.setString('counter_title', _title);
    await widget.onChanged();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await pickDate(
      context: context,
      initialDate: _start ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    setState(() => _start = date);
    await _save();
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayaç başlığı'),
        content: TextField(controller: c, maxLength: 40, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    c.dispose();
    if (result == null || !mounted) return;
    setState(() => _title = result);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = _start == null
        ? null
        : DateTime.utc(now.year, now.month, now.day)
              .difference(
                DateTime.utc(_start!.year, _start!.month, _start!.day),
              )
              .inDays;
    return Scaffold(
      appBar: AppBar(title: const Text('Sayaç')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const Text('🗓️', style: TextStyle(fontSize: 40)),
                        Text(
                          _title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          days == null ? '—' : '$days',
                          style: TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Text(
                          days == null
                              ? 'Başlamak için bir tarih seç'
                              : 'gün geçti',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _pick,
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            _start == null
                                ? 'Başlangıç tarihi seç'
                                : '${_start!.day}.${_start!.month}.${_start!.year} • Değiştir',
                          ),
                        ),
                        TextButton(
                          onPressed: _rename,
                          child: const Text('Başlığı özelleştir'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
