import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessageSelectionScope extends StatefulWidget {
  final Widget child;
  const MessageSelectionScope({super.key, required this.child});
  static MessageSelectionData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessageSelectionData>();
  @override
  State<MessageSelectionScope> createState() => _MessageSelectionScopeState();
}

class _MessageSelectionScopeState extends State<MessageSelectionScope> {
  final _selected = <String, ({String text, int order})>{};
  void _toggle(String id, String text, int order) => setState(() {
    if (_selected.containsKey(id)) {
      _selected.remove(id);
    } else {
      _selected[id] = (text: text, order: order);
    }
  });
  @override
  Widget build(BuildContext context) => MessageSelectionData(
    ids: _selected.keys.toSet(),
    toggle: _toggle,
    child: Stack(
      children: [
        widget.child,
        if (_selected.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                elevation: 4,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Seçimi kapat',
                        onPressed: () => setState(_selected.clear),
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text('${_selected.length} mesaj seçildi'),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Kopyala'),
                        onPressed: () async {
                          final items = _selected.entries.toList()
                            ..sort((a, b) {
                              final order = a.value.order.compareTo(
                                b.value.order,
                              );
                              return order != 0
                                  ? order
                                  : a.key.compareTo(b.key);
                            });
                          await Clipboard.setData(
                            ClipboardData(
                              text: items.map((e) => e.value.text).join('\n\n'),
                            ),
                          );
                          if (mounted) setState(_selected.clear);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class MessageSelectionData extends InheritedWidget {
  final Set<String> ids;
  final void Function(String, String, int) toggle;
  const MessageSelectionData({
    super.key,
    required this.ids,
    required this.toggle,
    required super.child,
  });
  @override
  bool updateShouldNotify(MessageSelectionData oldWidget) => true;
}
