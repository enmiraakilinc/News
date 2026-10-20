import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çevrimdışı yemek tarifi defteri. Her tarif: ad + malzemeler
/// (miktar · ölçü · malzeme) + yapılışı. Tamamen cihazda saklanır (internet yok).
class RecipeBookScreen extends StatefulWidget {
  const RecipeBookScreen({super.key});

  @override
  State<RecipeBookScreen> createState() => _RecipeBookScreenState();
}

class _RecipeBookScreenState extends State<RecipeBookScreen> {
  static const String _key = 'recipes_v1';
  List<Map<String, dynamic>> _recipes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<Map<String, dynamic>> list = [];
    if (raw != null && raw.isNotEmpty) {
      list = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _recipes = list;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_recipes));
  }

  Future<void> _addOrEdit([int? index]) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _RecipeEditScreen(recipe: index != null ? _recipes[index] : null),
      ),
    );
    if (result == null) return;
    setState(() {
      if (index != null) {
        _recipes[index] = result;
      } else {
        _recipes.add(result);
      }
    });
    await _save();
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tarifi sil"),
        content: Text('"${_recipes[index]['name']}" silinecek. Emin misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _recipes.removeAt(index));
      await _save();
    }
  }

  void _open(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RecipeDetailScreen(
          recipe: _recipes[index],
          onEdit: () => _addOrEdit(index),
          onDelete: () => _delete(index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Yemek Tarifleri")),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("Tarif Ekle"),
        onPressed: () => _addOrEdit(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _recipes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Henüz tarif yok.\n'Tarif Ekle' ile ilk tarifini yaz 🍳",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: _recipes.length,
              itemBuilder: (c, i) {
                final r = _recipes[i];
                final ingCount = (r['ingredients'] as List?)?.length ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Text("🍽️", style: TextStyle(fontSize: 28)),
                    title: Text(
                      (r['name'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text("$ingCount malzeme"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(i),
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────────────────
//  TARİF DETAYI
// ─────────────────────────────────────────
class _RecipeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> recipe;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RecipeDetailScreen({
    required this.recipe,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ingredients = (recipe['ingredients'] as List?) ?? [];
    final steps = (recipe['steps'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text((recipe['name'] ?? '').toString()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.pop(context);
              onEdit();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Malzemeler",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (ingredients.isEmpty)
            const Text("—", style: TextStyle(color: Colors.grey))
          else
            ...ingredients.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              final amount = (m['amount'] ?? '').toString().trim();
              final unit = (m['unit'] ?? '').toString().trim();
              final name = (m['name'] ?? '').toString().trim();
              final olcu = [amount, unit].where((s) => s.isNotEmpty).join(' ');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("•  "),
                    Expanded(
                      child: Text(
                        olcu.isEmpty ? name : "$olcu  $name",
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 20),
          const Text(
            "Yapılışı",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            steps.isEmpty ? "—" : steps,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  TARİF EKLE / DÜZENLE
// ─────────────────────────────────────────
class _RecipeEditScreen extends StatefulWidget {
  final Map<String, dynamic>? recipe;
  const _RecipeEditScreen({this.recipe});

  @override
  State<_RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<_RecipeEditScreen> {
  static const List<String> _units = [
    'adet',
    'gram',
    'kg',
    'ml',
    'litre',
    'su bardağı',
    'çay bardağı',
    'yemek kaşığı',
    'tatlı kaşığı',
    'çay kaşığı',
    'tutam',
    'paket',
    'diş',
    'dilim',
    'demet',
  ];

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _stepsCtrl = TextEditingController();

  /// Her malzeme satırı: amount ve name için controller, unit için seçili değer.
  final List<_IngredientRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    if (r != null) {
      _nameCtrl.text = (r['name'] ?? '').toString();
      _stepsCtrl.text = (r['steps'] ?? '').toString();
      for (final e in (r['ingredients'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        _rows.add(
          _IngredientRow(
            amount: (m['amount'] ?? '').toString(),
            unit: _units.contains(m['unit'])
                ? m['unit'] as String
                : _units.first,
            name: (m['name'] ?? '').toString(),
          ),
        );
      }
    }
    if (_rows.isEmpty) _rows.add(_IngredientRow(unit: _units.first));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stepsCtrl.dispose();
    for (final r in _rows) {
      r.amountCtrl.dispose();
      r.nameCtrl.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_IngredientRow(unit: _units.first)));
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].amountCtrl.dispose();
      _rows[i].nameCtrl.dispose();
      _rows.removeAt(i);
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Tarif adı gerekli.")));
      return;
    }
    // Boş malzeme satırlarını atla.
    final ingredients = _rows
        .where((r) => r.nameCtrl.text.trim().isNotEmpty)
        .map(
          (r) => {
            'amount': r.amountCtrl.text.trim(),
            'unit': r.unit,
            'name': r.nameCtrl.text.trim(),
          },
        )
        .toList();

    Navigator.pop(context, {
      'name': name,
      'ingredients': ingredients,
      'steps': _stepsCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? "Yeni Tarif" : "Tarifi Düzenle"),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              "KAYDET",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: "Tarif adı",
              hintText: "Örn: Menemen",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Malzemeler",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Malzeme"),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < _rows.length; i++) _buildRow(i),
          const SizedBox(height: 20),
          const Text(
            "Yapılışı",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _stepsCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: "1. Soğanı kavur...\n2. Domatesi ekle...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRow(int i) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Miktar
          SizedBox(
            width: 56,
            child: TextField(
              controller: row.amountCtrl,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: "2",
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Ölçü
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<String>(
              initialValue: row.unit,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                border: OutlineInputBorder(),
              ),
              items: _units
                  .map(
                    (u) => DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => row.unit = v ?? _units.first),
            ),
          ),
          const SizedBox(width: 6),
          // Malzeme adı
          Expanded(
            child: TextField(
              controller: row.nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: "malzeme",
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: Colors.grey,
            onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
          ),
        ],
      ),
    );
  }
}

/// Düzenleme ekranındaki tek bir malzeme satırının durumu.
class _IngredientRow {
  final TextEditingController amountCtrl;
  final TextEditingController nameCtrl;
  String unit;

  _IngredientRow({String amount = '', String name = '', required this.unit})
    : amountCtrl = TextEditingController(text: amount),
      nameCtrl = TextEditingController(text: name);
}
