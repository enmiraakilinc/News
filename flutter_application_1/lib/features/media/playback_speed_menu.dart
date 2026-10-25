import 'package:flutter/material.dart';

class PlaybackSpeedMenu extends StatelessWidget {
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  const PlaybackSpeedMenu({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  static String label(double rate) =>
      '${rate == rate.roundToDouble() ? rate.toInt() : rate}x';
  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
    requestFocus: false,
    tooltip: 'Oynatma hızı',
    enabled: enabled,
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final rate in [1.0, 1.5, 2.0])
        PopupMenuItem(value: rate, child: Text(label(rate))),
    ],
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        label(value),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
