# Android live share — review follow-ups for files owned elsewhere

The Android screen-share review (H1, M1–M4, L1–L8) was fixed in `android_share.dart`,
`ScreenCaptureService.kt`, `LiveAudioInterruptions.kt` and the flutter_webrtc fork
(`nextbrain/1.6.2-hotfix.4`). The changes below belong to files other sessions were editing at
the time (`room.dart`, `room_screen_share.dart`, `share_options_sheet.dart`, `MainActivity.kt`);
each is small and independent. The new gate API is unit-tested in `test/org/live_mic_gate_test.dart`.

## M1 — the Android share must honour `shareAudioAllowed` (room_screen_share.dart)

1. `_toggleScreenShareAndroid`, where the sheet is offered: ask the native side with the room's
   permissions, so the switch is not shown when the mic or the share audio is not allowed (M2 too):

   ```dart
   final local = room.localParticipant; // already the `local` parameter
   final audioSupported = await AndroidShareNative.deviceAudioSupported(
     micAllowed: ParticipantMic(local).allowed,
     shareAudioAllowed: shareAudioAllowed,
   );
   ```

   (`shareDeviceAudioAvailable(apiLevel ≥ 29, micAllowed, shareAudioAllowed)` decides; same rule as
   the web path's `displayAudioSupported() && shareAudioAllowed`.)
2. After the publish: `beginDeviceAudio` now returns `false` when the mic may not be published or
   its track could not come on. Replace

   ```dart
   if (outcome.deviceAudioOn) {
     await LiveMicGate.instance.beginDeviceAudio(local);
   } else if ...
   ```

   with

   ```dart
   if (outcome.deviceAudioOn) {
     if (!await LiveMicGate.instance.beginDeviceAudio(local)) {
       showSnack(t('يُشارَك بلا صوت الجهاز', 'Sharing without device audio'));
     }
   } else if ...
   ```

   so no exception reaches the catch that tears the share down.
3. Revoked mid-share (room.dart `_onLocalPermissions`): today only a revoked `screen_share` or a
   revoked microphone during device audio stops the share. Also stop it when `screen_share_audio`
   goes away while device audio rides on the mic track (the native capture cannot be detached on
   its own without a new channel method, so the share restarts without audio is the simplest
   correct answer):

   ```dart
   if (revoked.contains(TrackSource.screenShareVideo) ||
       (LiveMicGate.instance.deviceAudioActive &&
        (revoked.contains(TrackSource.microphone) || (before.shareAudio && !next.shareAudio)))) {
     await stopScreenShare();
   }
   ```

   (`liveRevokedSources` only lists *published* sources, and on Android the share audio is not a
   published `screenShareAudio` track, hence the explicit `before.shareAudio && !next.shareAudio`.)

## M3 — "muted by the call" now lives in LiveMicGate (room_screen_share.dart)

Delete the `bool _micMutedByCall = false;` field and replace the body of `_onPhoneCall`'s `try`:

```dart
if (active) {
  if (await gate.muteForCall(local)) {
    showSnack(t('أُوقف الميكروفون أثناء المكالمة الهاتفية', 'Microphone muted during the phone call'));
  }
} else if (await gate.restoreAfterCall(local)) {
  showSnack(t('عاد الميكروفون بعد المكالمة', 'Microphone back on after the call'));
}
```

Every tap through `LiveMicGate.setMic` / `toggle` (control bar, mini box) clears the gate's
`mutedByCall`, so the call's end only gives back a mic the call itself muted, and
`reset()` / `release()` forget it with the room.

## L1 — release the gate before the disconnect (room.dart)

`LiveMicGate.reset()` (called from `disposeLiveNativeEvents()` in the room's `dispose`) is
synchronous and clears the native soft mute at once; if the room is still connected and
soft-muted, the mic is audible for the tens of ms until the disconnect lands. Await the new
`release` before leaving, in `_endSessionWithRecording()` right before `_leaveRoom();` (and in any
other path that leaves on purpose, e.g. the back-swipe / Leave button that reaches `_leaveRoom`):

```dart
if (!kIsWeb && lkPlatformIs(PlatformType.android)) {
  await LiveMicGate.instance.release(widget.room.localParticipant);
}
_leaveRoom();
```

`release` mutes a soft-muted mic for real (retried once) and only then clears the native flag;
if the mute fails it keeps the soft mute and `reset()` clears it after the disconnect.
`reset()` stays where it is (it now always clears the native flag: H1).

## M4 — MainActivity's projection start (MainActivity.kt)

1. `onActivityResult(REQUEST_MEDIA_PROJECTION)`: wrap the start in a try/catch that answers Dart,
   otherwise a refused `startForegroundService` (background-start rules, `ForegroundServiceStartNotAllowedException`
   on 12+) leaves the Dart `startScreenCaptureService` call waiting forever:

   ```kotlin
   try {
       if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
           startForegroundService(i) else startService(i)
   } catch (e: Exception) {
       Log.e(TAG, "onActivityResult(1001): could not start the service: ${e.message}", e)
       ScreenCaptureService.onProjectionGrantStored = null
       onRecorderProjectionApproved?.invoke(mapOf("ok" to false, "error" to (e.message ?: "service start failed")))
       onRecorderProjectionApproved = null
   }
   ```
2. In `"startScreenCaptureService"`, before `startActivityForResult(createScreenCaptureIntent())`,
   when no recording runs (`!ScreenCaptureService.isRunning`) and RECORD_AUDIO is granted, start the
   service with a microphone-typed foreground start first (a new action, e.g.
   `ACTION_PREPARE_SHARE`, answered in `onStartCommand` with `startForegroundTyped(FOREGROUND_SERVICE_TYPE_MICROPHONE)`)
   while the activity is still in front: the service is then already a foreground service when
   the consent result arrives, so the later `startForegroundService(STORE_PROJECTION)` cannot be
   refused by the background-start rules, and the microphone type (needed for device audio and
   WebRTC's mic in another app) is granted under the while-in-use rules. On a denied consent the
   service stops itself through `answerForegroundStart()` (STORE_PROJECTION is never sent: add a
   `stopService` in the `else` branch of `onActivityResult`). `ScreenCaptureService.foregroundBeforeStop()`
   (L3) already covers a start whose `startForeground` threw.

## L6 — stop the audio-interruption watcher with the Activity (MainActivity.kt)

`LiveAudioInterruptions` now holds the application context's AudioManager, but
`ElFaheemBridge.audioFocusListener` is static and its lambda captures the watcher; add

```kotlin
override fun onDestroy() {
    audioInterruptions?.stop()
    audioInterruptions = null
    super.onDestroy()
}
```

(MainActivity has no `onDestroy` yet; the EventChannel's `onCancel` is not called when the
Activity is destroyed with the engine.)

## L7 — the device-audio scope note (share_options_sheet.dart)

Playback capture takes every app's media audio, also in an Android 14 single-app share (the
system picker's "A single app"). Show `shareDeviceAudioScopeNote(arabic: AppConfig.lang == 'ar')`
(android_share.dart) as a second subtitle line of the `share.device_audio` `AppSwitchTile` when
`!web`, i.e. after `'Viewers hear videos and apps; call audio is never captured'`. No behaviour
change. Check `test/ui/share_options_layout_test.dart` still passes at 320 px with `textScaler` 1.3.
