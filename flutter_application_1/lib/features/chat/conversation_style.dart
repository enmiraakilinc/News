import 'dart:ui';
import 'package:flutter/material.dart';
import 'reaction_picker.dart';

/// The supplied conversation reference, expressed through the active theme.
class ConversationColors {
  final ColorScheme scheme;
  const ConversationColors(this.scheme);
  Color get background => scheme.surface;
  Color get panel => scheme.surfaceContainerLowest;
  Color get sent => scheme.primaryContainer;
  Color get onSent => scheme.onPrimaryContainer;
  Color get received => panel;
  Color get onReceived => scheme.onSurface;
  Color get line => scheme.outlineVariant.withValues(alpha: .45);
}

class ConversationAction {
  final String value, label;
  final IconData icon;
  final bool destructive;
  const ConversationAction(
    this.value,
    this.label,
    this.icon, {
    this.destructive = false,
  });
}

Future<String?> showConversationActions(
  BuildContext context, {
  required String preview,
  required bool mine,
  required List<ConversationAction> actions,
  String? quoted,
  String? time,
  bool reactions = false,
}) => showDialog<String>(
  context: context,
  requestFocus: false,
  animationStyle: AnimationStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    reverseDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 100),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ),
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .24),
  builder: (context) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
    child: Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: _ConversationActions(
            preview: preview,
            mine: mine,
            actions: actions,
            reactions: reactions,
            quoted: quoted,
            time: time,
          ),
        ),
      ),
    ),
  ),
);

class _ConversationActions extends StatefulWidget {
  final String preview;
  final String? quoted, time;
  final bool mine, reactions;
  final List<ConversationAction> actions;
  const _ConversationActions({
    required this.preview,
    required this.mine,
    required this.actions,
    required this.reactions,
    this.quoted,
    this.time,
  });
  @override
  State<_ConversationActions> createState() => _ConversationActionsState();
}

class _ConversationActionsState extends State<_ConversationActions> {
  late final _favorites = loadReactionFavorites();
  @override
  Widget build(BuildContext context) {
    final colors = ConversationColors(Theme.of(context).colorScheme);
    final scheme = colors.scheme;
    final foreground = widget.mine ? colors.onSent : colors.onReceived;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (widget.reactions)
          FutureBuilder<List<String>>(
            future: _favorites,
            builder: (context, snapshot) => Material(
              color: colors.panel,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final emoji
                        in (snapshot.data ?? const <String>[]).take(6))
                      ConversationPressFeedback(
                        child: IconButton(
                          style: IconButton.styleFrom(
                            minimumSize: const Size(40, 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          tooltip: '$emoji ifadesini bırak',
                          onPressed: () =>
                              Navigator.pop(context, 'emoji:$emoji'),
                          icon: Text(
                            emoji,
                            style: const TextStyle(fontSize: 23),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 44,
                          ),
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                    ConversationPressFeedback(
                      child: IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        tooltip: 'Diğer ifadeler',
                        onPressed: () => Navigator.pop(context, 'reaction'),
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.mine ? colors.sent : colors.received,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.quoted != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.quoted!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground.withValues(alpha: .85),
                      fontSize: 12,
                    ),
                  ),
                ),
              Text(
                widget.preview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground, fontSize: 15, height: 1.45),
              ),
              if (widget.time != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      widget.time!,
                      style: TextStyle(
                        fontSize: 10,
                        color: foreground.withValues(alpha: .75),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: colors.panel,
          elevation: 8,
          shadowColor: scheme.shadow.withValues(alpha: .16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in widget.actions) ...[
                  if (action.destructive)
                    Divider(height: 9, color: colors.line),
                  ListTile(
                    minTileHeight: 46,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(
                      action.icon,
                      size: 22,
                      color: action.destructive
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 15,
                        color: action.destructive
                            ? scheme.error
                            : scheme.onSurface,
                        fontWeight: action.destructive
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, action.value),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ConversationSection extends StatelessWidget {
  final List<Widget> children;
  const ConversationSection({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final colors = ConversationColors(Theme.of(context).colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: colors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.line),
        ),
        // Text and large accessibility fonts must not be clipped by card corners.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// A small paint-only response; no timers, loops, list animations or layout work.
class ConversationPressFeedback extends StatefulWidget {
  final Widget child;
  const ConversationPressFeedback({super.key, required this.child});
  @override
  State<ConversationPressFeedback> createState() =>
      _ConversationPressFeedbackState();
}

class _ConversationPressFeedbackState extends State<ConversationPressFeedback> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: !reduced && _pressed ? .96 : 1,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class ConversationMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const ConversationMenuLabel({
    super.key,
    required this.icon,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Flexible(child: Text(label, style: const TextStyle(fontSize: 14))),
    ],
  );
}
