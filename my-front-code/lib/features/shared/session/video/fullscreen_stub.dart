// Non-web platforms: fullscreen is handled with SystemChrome in the player.
Future<bool> enterLandscapeFullscreen() async => false;

Future<void> exitLandscapeFullscreen() async {}

/// Returns a function that removes the listener.
void Function() onFullscreenExit(void Function() onExit) => () {};
