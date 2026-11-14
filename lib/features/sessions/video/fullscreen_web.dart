// Web only: real browser fullscreen + landscape orientation lock.
// Chrome / Android allow the lock while in fullscreen; iOS Safari does not
// (the player then rotates itself — see _webForceRotate).
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Enters fullscreen and locks landscape. Returns true if the lock succeeded.
Future<bool> enterLandscapeFullscreen() async {
  try {
    if (web.document.fullscreenElement == null) {
      await web.document.documentElement!.requestFullscreen().toDart;
    }
  } catch (_) {}
  try {
    await web.window.screen.orientation.lock('landscape').toDart;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> exitLandscapeFullscreen() async {
  try {
    web.window.screen.orientation.unlock();
  } catch (_) {}
  try {
    if (web.document.fullscreenElement != null) {
      await web.document.exitFullscreen().toDart;
    }
  } catch (_) {}
}

/// Calls [onExit] when the browser leaves fullscreen (Esc, back gesture...).
/// Returns a function that removes the listener.
void Function() onFullscreenExit(void Function() onExit) {
  final fn = ((web.Event _) {
    if (web.document.fullscreenElement == null) onExit();
  }).toJS;
  web.document.addEventListener('fullscreenchange', fn);
  return () => web.document.removeEventListener('fullscreenchange', fn);
}
