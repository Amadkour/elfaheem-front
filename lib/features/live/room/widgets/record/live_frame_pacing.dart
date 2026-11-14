// D-135: how often the Android recorder gets a frame of the room before a share.
//
// The device recording draws the room from frames Dart sends (RepaintBoundary.toImage → raw RGBA → the native
// renderer, which encodes 15 fps). They used to be PNGs every 500 ms: the camera moved in ~2 fps jumps in the
// recording ("slow motion"). Now the next capture is scheduled as soon as the previous one is done, at most
// [kLiveFrameMaxFps] a second, and never spending more than half the time capturing (a slow device simply
// gets fewer frames instead of a busy UI thread).
//
// D-110: this is now the FALLBACK. The native side copies the room from Flutter's own surface at 30 fps
// (RoomFrameGrabber.kt, the recorder encodes 30 fps); Dart's frames (~55 ms each on the S24, ~9 a second) are sent
// only when that copy does not work on the device.

/// The frame rate the Dart room capture aims for (the fallback, D-110).
const int kLiveFrameMaxFps = 12;

/// The shortest gap between two capture starts.
const Duration kLiveFrameMinPeriod = Duration(milliseconds: 1000 ~/ kLiveFrameMaxFps);

/// The wait before the next capture, given how long the last one took ([spent]): the period is
/// max(kLiveFrameMinPeriod, 2 × spent) — at most 50 % of the time is spent capturing.
Duration liveFrameDelay(Duration spent) {
  final period = spent * 2 > kLiveFrameMinPeriod ? spent * 2 : kLiveFrameMinPeriod;
  final wait = period - spent;
  return wait.isNegative ? Duration.zero : wait;
}
