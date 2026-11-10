// companion_platform_web.dart — the browser side of companion_platform.dart (D-520).
library;

import 'dart:js_interop';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:web/web.dart' as web;

bool companionRunsOnPhone() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  if (ua.contains('iphone') || ua.contains('android') || ua.contains('mobi')) return true;
  // iPadOS asks for desktop pages and reports a Mac.
  return ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1;
}

String companionOriginLabel() {
  final ua = web.window.navigator.userAgent;
  final browser = ua.contains('Edg/')
      ? 'Edge'
      : ua.contains('OPR/')
          ? 'Opera'
          : ua.contains('Firefox/')
              ? 'Firefox'
              : ua.contains('Chrome/')
                  ? 'Chrome'
                  : ua.contains('Safari/')
                      ? 'Safari'
                      : 'browser';
  final os = ua.contains('Windows')
      ? 'Windows'
      : ua.contains('Mac OS')
          ? 'Mac'
          : ua.contains('Linux')
              ? 'Linux'
              : '';
  return os.isEmpty ? browser : '$browser on $os';
}

/// LiveKit plays each remote audio track through its own `<audio id="livekit_audio_<cid>">` element. Muting the element
/// silences this device and leaves the track alive, so a recording running here keeps the sound.
void companionSetPlayback(String cid, rtc.MediaStreamTrack track, {required bool muted}) {
  final el = web.document.getElementById('livekit_audio_$cid');
  if (el == null || !el.instanceOfString('HTMLAudioElement')) return;
  (el as web.HTMLAudioElement).muted = muted;
}
