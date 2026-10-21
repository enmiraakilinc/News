import 'package:flutter/material.dart';

/// Separate local microphone, audio route, and incoming sound controls.
class CallControls extends StatelessWidget {
  final bool muted,
      speakerOn,
      receiveMuted,
      video,
      cameraOff,
      audioBusy,
      enabled;
  final VoidCallback onMicrophone, onSpeaker, onReceive;
  final VoidCallback? onCamera, onSwitchCamera;
  const CallControls({
    super.key,
    required this.muted,
    required this.speakerOn,
    required this.receiveMuted,
    required this.video,
    required this.cameraOff,
    required this.audioBusy,
    required this.enabled,
    required this.onMicrophone,
    required this.onSpeaker,
    required this.onReceive,
    this.onCamera,
    this.onSwitchCamera,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 16,
    runSpacing: 16,
    children: [
      _CallControl(
        label: 'Mikrofon',
        active: !muted,
        icon: muted ? Icons.mic_off : Icons.mic,
        tooltip: muted ? 'Mikrofonu aç' : 'Mikrofonu kapat',
        onPressed: enabled ? onMicrophone : null,
      ),
      _CallControl(
        label: 'Hoparlör',
        active: speakerOn,
        icon: speakerOn ? Icons.volume_up : Icons.hearing,
        tooltip: speakerOn ? 'Hoparlörü kapat' : 'Hoparlörü aç',
        onPressed: enabled && !audioBusy ? onSpeaker : null,
      ),
      _CallControl(
        label: 'Karşı ses',
        active: !receiveMuted,
        icon: receiveMuted ? Icons.volume_off : Icons.headphones,
        tooltip: receiveMuted
            ? 'Karşı tarafın sesini aç'
            : 'Karşı tarafın sesini kapat',
        onPressed: enabled && !audioBusy ? onReceive : null,
      ),
      if (video)
        _CallControl(
          label: 'Kamera',
          active: !cameraOff,
          icon: cameraOff ? Icons.videocam_off : Icons.videocam,
          tooltip: cameraOff ? 'Kamerayı aç' : 'Kamerayı kapat',
          onPressed: enabled ? onCamera : null,
        ),
      if (video)
        _CallControl(
          label: 'Kamera değiştir',
          active: null,
          icon: Icons.cameraswitch,
          tooltip: 'Kamerayı değiştir',
          onPressed: enabled ? onSwitchCamera : null,
        ),
    ],
  );
}

class _CallControl extends StatelessWidget {
  final String label, tooltip;
  final bool? active;
  final IconData icon;
  final VoidCallback? onPressed;
  const _CallControl({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.icon,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          toggled: active,
          child: IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: 28,
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(18),
              backgroundColor: active == true
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              foregroundColor: active == true
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
            icon: Icon(icon),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, maxLines: 2),
        if (active != null)
          Text(
            active! ? 'Açık' : 'Kapalı',
            style: Theme.of(context).textTheme.labelSmall,
          ),
      ],
    ),
  );
}
