import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import 'recipe_screen.dart';

class DecoyHomeScreen extends StatelessWidget {
  final VoidCallback onBack;
  const DecoyHomeScreen({super.key, required this.onBack});

  Widget _aracKart(
    BuildContext context,
    String emoji,
    String baslik,
    Widget ekran,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => ekran)),
      child: Container(
        decoration: BoxDecoration(
          color: kSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kSoftBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(
              baslik,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Araçlar"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        children: [
          _aracKart(context, "🍳", "Yemek Tarifleri", const RecipeBookScreen()),
          _aracKart(
            context,
            "✅",
            "Yapılacaklar",
            FakeTodoScreen(onBack: () => Navigator.pop(context)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  SAHTE EKRAN  (Not / Yapılacaklar — decoy)
// ─────────────────────────────────────────
class FakeTodoScreen extends StatefulWidget {
  final VoidCallback onBack;
  const FakeTodoScreen({super.key, required this.onBack});

  @override
  State<FakeTodoScreen> createState() => _FakeTodoScreenState();
}

class _FakeTodoScreenState extends State<FakeTodoScreen> {
  // Gerçek gizli notlardan ('my_notes') tamamen ayrı bir depolama kullanır.
  static const String _storageKey = 'decoy_todos';

  // Her öğe: { "text": String, "done": bool }
  List<Map<String, dynamic>> _todos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _todos = decoded
            .map(
              (e) => {
                'text': (e['text'] ?? '').toString(),
                'done': e['done'] == true,
              },
            )
            .toList();
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_todos));
  }

  void _addTodo() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Yeni Görev"),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: "Ne yapılacak?"),
          onSubmitted: (_) => _commitAdd(ctx, c.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () => _commitAdd(ctx, c.text),
            child: const Text("Ekle"),
          ),
        ],
      ),
    );
  }

  void _commitAdd(BuildContext dialogCtx, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      Navigator.pop(dialogCtx);
      return;
    }
    setState(() => _todos.add({'text': t, 'done': false}));
    _save();
    Navigator.pop(dialogCtx);
  }

  void _toggle(int i) {
    setState(() => _todos[i]['done'] = !(_todos[i]['done'] as bool));
    _save();
  }

  void _delete(int i) {
    setState(() => _todos.removeAt(i));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final int remaining = _todos.where((e) => e['done'] != true).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onBack,
        ),
        title: const Text("Notlar"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTodo,
        child: const Icon(Icons.add),
      ),
      body: _todos.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist_rtl, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    "Henüz görev yok.\nEklemek için + butonuna dokun.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        remaining == 0
                            ? "Tüm görevler tamamlandı 🎉"
                            : "$remaining görev bekliyor",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (c, i) {
                      final done = _todos[i]['done'] == true;
                      return Dismissible(
                        key: ValueKey('${_todos[i]['text']}_$i'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _delete(i),
                        child: CheckboxListTile(
                          controlAffinity: ListTileControlAffinity.leading,
                          value: done,
                          onChanged: (_) => _toggle(i),
                          title: Text(
                            _todos[i]['text'].toString(),
                            style: TextStyle(
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: done ? Colors.grey : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────
//  TAM EKRAN RESİM
// ─────────────────────────────────────────
