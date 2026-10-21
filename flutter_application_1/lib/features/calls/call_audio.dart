import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Only affects the remote call tracks, never the phone's global volume.
Future<void> setCallReceiveMuted(
  Iterable<MediaStreamTrack> tracks,
  bool muted,
) async {
  for (final track in tracks.toList()) {
    if (track.kind != 'audio') continue;
    track.enabled = !muted;
    await Helper.setVolume(muted ? 0 : 1, track);
  }
}
