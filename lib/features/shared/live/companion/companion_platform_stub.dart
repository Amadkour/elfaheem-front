// companion_platform_stub.dart — the native side of companion_platform.dart (D-520).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Phones (a phone browser counts on the web side): the device that gets the prompt.
bool companionRunsOnPhone() =>
    defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

String companionOriginLabel() => 'computer';

/// A room's audio on this device: desktop apps have no audio element, the volume of the track is it.
void companionSetPlayback(String cid, rtc.MediaStreamTrack track, {required bool muted}) {
  try {
    rtc.Helper.setVolume(muted ? 0.0 : 1.0, track);
  } catch (_) {
    // A platform without per-track volume: nothing more to do.
  }
}
