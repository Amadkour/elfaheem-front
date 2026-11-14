# room.dart wiring still owed (Android share follow-ups, live-call service, annotation overlay)

The pieces below are done in the files around the room (`widgets/room_screen_share.dart`, `share_options_sheet.dart`,
`android_share.dart`, `widgets/live_call_service.dart`, `MainActivity.kt`, `LiveCallService.kt`,
`ScreenCaptureService.kt`); each needs a small call in `room.dart`, which another session was editing at the time.
Apply them together; none changes behaviour on iOS / web.

## 1. M1 (3): a revoked share audio stops a share with device audio

`_onLocalPermissions`: replace the share condition with

```dart
if (revoked.contains(TrackSource.screenShareVideo)) {
  await stopScreenShare();
} else {
  await stopShareIfDeviceAudioRevoked(
    micRevoked: revoked.contains(TrackSource.microphone),
    shareAudioRevoked: before.shareAudio && !next.shareAudio,
  );
}
```

`stopShareIfDeviceAudioRevoked` (RoomScreenShareMixin) is a no-op off Android or without device audio, stops the
share otherwise and says why (`showSnack`). The explicit `before.shareAudio && !next.shareAudio` is needed:
`liveRevokedSources` lists published sources only, and on Android the share audio rides on the mic track.

## 2. L1: release the mic gate before the disconnect

In `_endSessionWithRecording()` right before `_leaveRoom();`, and in every other path that leaves on purpose
(Leave button, back-swipe, the mini box's hang-up, the live-call notification's Leave once confirmed):

```dart
if (!kIsWeb && lkPlatformIs(PlatformType.android)) {
  await LiveMicGate.instance.release(widget.room.localParticipant);
}
_leaveRoom();
```

`reset()` in `disposeLiveNativeEvents()` stays.

## 3. Live-call service (Android 14+ background microphone)

`import 'widgets/live_call_service.dart';`

- Once connected (where `initLiveNativeEvents()` runs) and whenever `_allowed.mic` turns true (`_onLocalPermissions`):
  `if (_allowed.mic) unawaited(LiveCallService.start());` — a student without a publishable mic needs nothing
  (a listen-only participant's playback is not cut in the background). Guests (`isGuest`) may call it too: it is a
  local service, no API.
- When the mic is no longer allowed: `unawaited(LiveCallService.stop());`
- `dispose()` (and `_leaveRoom`, before the pop): `unawaited(LiveCallService.stop()); LiveCallService.onLeaveRequested = null;`
- `initState`: `LiveCallService.onLeaveRequested = () { if (mounted) unawaited(_leaveFromMiniBox()); };` — the
  notification's Leave only brings the app to the front; `_leaveFromMiniBox` already expands a minimized room,
  asks the usual disconnect confirmation and ends through `_endSessionWithRecording()`.

Native rules, nothing to do in Dart: the service steps aside while `ScreenCaptureService` holds the microphone type
(recording or share) and comes back when it ends; a start the background refused is retried on the next resume.

## 4. Annotation: the Android whole-screen overlay (annotation_wiring.md step 6)

The share flow now offers the overlay itself after an Android share is published (feature key `live.annotation`;
"Display over other apps" asked once per room with an explanation; refused → nothing said, the in-app annotation
stays) and hides it on every stop path (our Stop, the system's Stop via `shareStopped`, a revoked permission,
`disposeLiveNativeEvents`). It sets `AndroidAnnotationOverlay.onClosed` itself, so room.dart must NOT set it
(annotation_wiring.md step 2 / 6.4 are replaced by this):

```dart
// RoomScreenShareMixin: the overlay's starting colour / thickness come from the controller
@override int? get annotationColorArgb => _annot.colorArgb;
@override int get annotationThickness => _annot.thickness;

// initState
annotationOverlayActive.addListener(_onAnnotOverlay);
// dispose (before _annot.dispose())
annotationOverlayActive.removeListener(_onAnnotOverlay);

void _onAnnotOverlay() {
  if (!mounted) return;
  final on = annotationOverlayActive.value;
  _annot.setBurnedIn(on); // needs _syncAnnotRoles() to have made the local presenter the lead
  if (on) setState(() => _annotOpen = false); // the native toolbar replaces the in-app one
}
```

Order: `_syncAnnotRoles()` must have run after the local share was published (it does: `_sortParticipants()` runs
on LocalTrackPublishedEvent) or `setBurnedIn` is ignored. The step-2 `dispose` line becomes only
`_annot.dispose();` (the overlay is hidden by `disposeLiveNativeEvents()`).

Known limit: Android 14+ lets the person pick "A single app" in the system dialog, and an overlay is not part of a
single-app capture, so viewers would not see burned-in strokes then. No public API tells which was picked; a
follow-up in `ScreenCaptureService` could pass `MediaProjectionConfig.createConfigForDefaultDisplay()` when the
presenter wants to draw over other apps.
