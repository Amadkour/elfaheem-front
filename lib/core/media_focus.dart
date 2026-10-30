// lib/core/media_focus.dart — one sound at a time (D-104).
//
// Whoever starts playing claims the focus; whoever held it before and asked to be told ([onLost]) stops. The
// course audio bar (listen-only, vod_listen.dart) asks to be told, so opening another lecture's player or joining
// a live room (RoomPage) stops it. The live room and the full player only claim: nothing else stops them.
library;

import 'package:flutter/foundation.dart';

class MediaFocus {
  MediaFocus._();

  static final Map<Object, VoidCallback?> _holders = <Object, VoidCallback?>{};

  /// [owner] starts playing: every other holder that asked to be told stops.
  static void claim(Object owner, {VoidCallback? onLost}) {
    final others = _holders.entries.where((e) => !identical(e.key, owner)).toList();
    for (final e in others) {
      _holders.remove(e.key);
    }
    _holders[owner] = onLost;
    for (final e in others) {
      e.value?.call();
    }
  }

  /// [owner] stopped playing.
  static void release(Object owner) => _holders.remove(owner);

  static bool holds(Object owner) => _holders.containsKey(owner);

  @visibleForTesting
  static void reset() => _holders.clear();
}
