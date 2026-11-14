# iOS share — Dart wiring still owed (2026-10-29)

The native side (ios/, UNTESTED) and `lib/features/live/room/widgets/ios_share.dart`
(`IosShareNative`) are written. These existing Dart files were being edited by another agent, so
the changes below were NOT applied. Apply them, then run the Mac test plan
(`docs/live/ios_test_plan.md`). Audit ids: `docs/live/audit/ios_web.md`.

## How the new iOS flow works (read first)

1. Dart calls `IosShareNative.start()` → native `showBroadcastPicker` shows the system sheet for
   our extension and arms the in-app recorder. **Nothing is published yet.**
2. The user taps *Start Broadcast* → the extension posts `iOS_BroadcastStarted` →
   **livekit_client publishes the screen-share track by itself** (`BroadcastManager` listener →
   `setScreenShareEnabled(true)` with `RoomOptions.defaultScreenShareCaptureOptions`) →
   flutter_webrtc opens the `rtc_SSFD` socket → viewers see the screen. At the same moment
   `IosShareNative.broadcasting` turns `true`.
3. Stop: `IosShareNative.requestStop()` + `setScreenShareEnabled(false)`. Control Center stop,
   leaving the room, or the app dying all end at `iOS_BroadcastStopped` → LiveKit unpublishes,
   `IosShareNative.broadcasting` turns `false`.

**Rule:** on iOS never call `setScreenShareEnabled(true)` yourself before the broadcast runs:
livekit_client 2.13.1 (`local.dart` `setSourceEnabled`, iOS branch) answers it with
`BroadcastManager().requestActivation()`, i.e. a SECOND picker on top of ours.

## 1. `lib/features/live/room/prejoin.dart` — `RoomOptions` (≈ line 458) — I1

```dart
defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
  useiOSBroadcastExtension: true,   // NEW: deviceId 'broadcast-manual' on iOS (no-op elsewhere)
  captureScreenAudio: true,
  maxFrameRate: 30,                 // the extension sends ≤ 15 fps anyway
  params: VideoParametersPresets.screenShareH1080FPS15,
),
```

This MUST be in the room options (not only in a `setScreenShareEnabled(..., screenShareCaptureOptions:)`
call): LiveKit's auto-publish on `iOS_BroadcastStarted` passes no options.

Also check the same file around lines 503 / 533 (audit I6): any leftover `startLocalDebugSave` /
`stopLocalDebugSave` call must go — the native handlers are removed (an old call now gets
`MissingPluginException`/`notImplemented`).

## 2. `lib/features/live/room/widgets/room_screen_share.dart`

### 2a. `_toggleScreenShareIOS(local, isSharing)` — START branch (I1, I3, I5)

Replace the body of the `if (!isSharing)` branch with, in this order:

1. keep `recorder?.onBroadcastEvent = _handleBroadcastEvent;` and `recorder?.prepareUpgradeWait();`
   (only matters when recording);
2. **delete** the `unawaited(_safeNegotiate(() => local.setScreenShareEnabled(true)...))` call
   and the 300 ms delay (second picker, see the rule above);
3. **delete** the `local.setMicrophoneEnabled(true, audioCaptureOptions: _shareCompatibleAudioCaptureOptions)`
   block (I5: it switched WebRTC's echo cancellation off for the share → students heard echo; the
   native audio session now stays `playAndRecord` + `videoChat`). Delete the
   `_shareCompatibleAudioCaptureOptions` const and the matching "restore" block in
   `stopIOSBroadcast` (`_callQualityAudioCaptureOptions`) too, if nothing else uses them;
4. replace `await _ssChannel.invokeMethod<void>('showBroadcastPicker');` with
   `await IosShareNative.start();`
5. do NOT set `_isBroadcastActive = true` / `onIOSBroadcastStateChanged(true)` here any more
   (the user may still cancel the sheet). Set them from `IosShareNative.broadcasting` (2c);
6. `await recorder?.upgradeToScreenRecording();` stays, but only `if (recorder != null)` — without
   a recording there is nothing to wait for.

### 2b. `stopIOSBroadcast({bool leaving = false})` — I2

- Remove the early `if (!_isBroadcastActive) return;` guard or make it
  `if (!_isBroadcastActive && !IosShareNative.broadcasting.value) return;` — the extension may be
  live although Dart never saw the start (app restarted, LiveKit's own picker).
- Before `_ssChannel.invokeMethod('stopBroadcast')` add `await IosShareNative.requestStop();`
  (native `stopBroadcast` now posts the same stop request too, so either alone works; keep both,
  they are idempotent).
- `leaving: true` path: same — `requestStop()` then `stopBroadcast`; nothing else.

### 2c. Share state from the broadcast, not the publication (I3)

In the mixin (or in room.dart `initState` / `dispose`):

```dart
// initState (iOS only):
IosShareNative.bind();
IosShareNative.broadcasting.addListener(_onIosBroadcastingChanged);

void _onIosBroadcastingChanged() {
  final on = IosShareNative.broadcasting.value;
  if (on == _isBroadcastActive) return;
  _isBroadcastActive = on;
  onIOSBroadcastStateChanged(on);          // banner + toast
  if (on) {
    restartAudioTap();                     // the mic may be republished during negotiation
  } else {
    // Control Center stop: LiveKit unpublishes by itself; this is only belt and braces.
    unawaited(_safeNegotiate(() =>
        room.localParticipant?.setScreenShareEnabled(false).catchError((_) => null) ?? Future.value()));
  }
}

// dispose / disposeBroadcastSub():
IosShareNative.broadcasting.removeListener(_onIosBroadcastingChanged);
unawaited(IosShareNative.unbind());
```

`_handleBroadcastEvent`'s `broadcastStopped` branch (rec_events) can stay; it only fires while
recording and is idempotent with the listener above.

### 2d. `toggleScreenShare()` — which branch on iOS (I3)

`final isSharing = local.isScreenShareEnabled();` is false while the system sheet is open and
right after Start (publish not done yet), so a second tap re-ran START. On iOS use

```dart
final isSharing = lkPlatformIs(PlatformType.iOS)
    ? (IosShareNative.broadcasting.value || _isBroadcastActive || local.isScreenShareEnabled())
    : local.isScreenShareEnabled();
```

`screenShareActive` already includes `_isBroadcastActive`; add `IosShareNative.broadcasting.value`.

## 3. `lib/features/live/room/widgets/controls.dart` — I3

`build()` (≈ line 408: `final isSharing = participant.isScreenShareEnabled();`) — on iOS OR it with
`IosShareNative.broadcasting.value` and rebuild on it (wrap the share action in a
`ValueListenableBuilder<bool>(valueListenable: IosShareNative.broadcasting, ...)` or listen in
`initState`). Otherwise the button shows "Share" while the broadcast is live but not yet published.

## 4. `lib/features/live/room/room.dart`

- **Leaving the room (≈ line 1286):** `stopIOSBroadcast(leaving: true)` stays; with 2b it now really
  ends the extension. No other change.
- **Mic tap batching (`_startLiveKitAudioTap`, ≈ line 732) — I14:** the native side now timestamps
  by sample count and accepts any frame size, so batch ~100 ms per call instead of one
  `invokeMethod('sendAudioFrame')` per 10 ms frame:

  ```dart
  final _tapBuffer = BytesBuilder(copy: false);
  int _tapFrames = 0;
  // in onFrame:
  _tapBuffer.add(frame.data);
  _tapFrames += frame.data.lengthInBytes ~/ (frame.channels * (frame.format.name == 'float32' ? 4 : 2));
  if (_tapFrames >= frame.sampleRate ~/ 10) {
    _audioFrameChannel.invokeMethod('sendAudioFrame', {
      'data': _tapBuffer.takeBytes(), 'sampleRate': frame.sampleRate,
      'channels': frame.channels, 'format': frame.format.name,
    });
    _tapFrames = 0;
  }
  ```
  Flush (send what is buffered) in `_stopLiveKitAudioTap` and drop the buffer when the format
  (rate / channels / format) changes between frames.
- **Optional (I11):** after sign-in / when the room opens, `IosShareNative.retryPendingUploads(token)`
  with the same token value `startMicRecording` receives. Kept chunks are retried on every
  `startMicRecording` anyway.

## 5. Optional UI

- `IosShareNative.setAppAudio(false)` — a switch "Share the app's sound" (default on). App sound
  rides on the **microphone** track: it is heard only while the teacher's mic is on (say so in the
  sheet). Gate it with the room's `screen_share_audio` rule (`shareAudioAllowed`) like Android.
- `IosShareNative.setDetailMode(true)` — the same "detail" preset as Android
  (`share_presets.dart`): frames up to 1920 px instead of 1280.

## 6. Not possible from the native side alone (documented limits)

- **App audio needs the mic on.** flutter_webrtc's only capture hook is the capture
  post-processing adapter of its audio processing module; it runs only while the microphone
  captures. A muted mic (LiveKit mute stops / mutes the engine input) means no app audio for viewers.
  A separate `screenShareAudio` track would need a custom `RTCAudioSource` fed with PCM, which the
  fork's iOS sources do not expose.
- **DRM content** (Netflix, Apple TV+, some banking apps) gives black frames and no `.audioApp`.
- **Background:** while the teacher is in another app the Flutter app keeps running only because
  the call's audio session is active (`audio` background mode). If the mic is unpublished and
  nothing plays, iOS may suspend the app and the live share freezes (the broadcast keeps going).
