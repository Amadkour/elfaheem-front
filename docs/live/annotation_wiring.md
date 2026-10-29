# Live annotation: wiring into the room (D-079)

The core is in `lib/features/teacher/sessions/live/annotation/` (protocol, controller, painter, layer, toolbar,
Android overlay wrapper) and `android/.../AnnotationOverlay.kt` + `AnnotationOverlayChannel.kt` (registered in
`MainActivity.configureFlutterEngine`, `SYSTEM_ALERT_WINDOW` in the manifest). Nothing in the room uses it yet:
these are the steps to apply once the files other sessions are editing (`room.dart`, `controls.dart`,
`room_screen_share.dart`, `live_data_route.dart`) are free. Tests that already cover the core:
`test/org/annotation_protocol_test.dart`, `test/org/annotation_controller_test.dart`,
`test/ui/annotation_toolbar_layout_test.dart`, `test/ui/annotation_layer_layout_test.dart`.

## 1. `widgets/live_data_route.dart`

Add a route for both topics, so the room never drops the packets as unknown:

```dart
import '../annotation/annotation_protocol.dart' show kAnnotTopic, kAnnotLaserTopic;
// enum LiveDataRoute { …, annotation, … }
case kAnnotTopic:
case kAnnotLaserTopic:
  return LiveDataRoute.annotation;
```

## 2. `room.dart`: the controller

In `_RoomPageState`:

```dart
late final AnnotationController _annot = AnnotationController(
  localIdentity: widget.room.localParticipant?.identity ?? '',
  send: (topic, bytes, reliable, {to}) async {
    final lp = widget.room.localParticipant;
    if (lp == null) return;
    await lp.publishData(bytes, reliable: reliable, topic: topic, destinationIdentities: to);
  },
);
bool _annotOpen = false; // the toolbar is shown
```

- First `didChangeDependencies` (or the first build): `_annot.setColor(annotPresetColors(context.colors).first.toARGB32())`.
- `dispose()`: `_annot.dispose(); AndroidAnnotationOverlay.onClosed = null; unawaited(AndroidAnnotationOverlay.hide());`.

## 3. `room.dart`: packets, roles, late joiners

- In the `DataReceivedEvent` switch:
  `case LiveDataRoute.annotation: _annot.receive(event.topic!, event.data, sender: p?.identity); return;`
  (`p?.identity` is the LiveKit sender. Never pass an identity read from the payload.)
- `_syncAnnotRoles()`: `hosts` = every identity in the room (local + remote) for which `isHostIdentity(id)` is
  true, plus the local identity when `widget.host` (meeting hosts); `presenter` = the identity of the participant
  whose `screenShareVideo` publication is on the stage (`_stageTracks.first` when `_isScreenShareMain`), else null.
  Call it from `_sortParticipants()` (it already runs on connect / disconnect / track (un)publish / local track
  events), i.e. `_annot.setRoles(hosts: …, presenter: …)`. It is a no-op when nothing changed.
- `..on<ParticipantConnectedEvent>((e) => _annot.onParticipantJoined(e.participant.identity))` (next to
  `_hands.reannounceLocal()`). Only the responder (presenter, else the first host by identity) sends.
- After the first connect and on `RoomReconnectedEvent`: `_annot.requestSnapshot()`.
- When the share on stage ends (presenter becomes null) or changes person: for the host, `_annot.clearAll()`
  (the drawings belonged to that content); everyone: `_annotOpen = false; _annot.setDrawMode(false)`.

## 4. `room.dart`: the layer over the shared video

In `_PremiumScreenShareView` (and the other places a screen share fills the stage), replace the
`VideoTrackRenderer` child of the `ClipRRect` with:

```dart
Stack(fit: StackFit.expand, children: [
  VideoTrackRenderer(screenTrack, renderMode: VideoRenderMode.auto, fit: VideoViewFit.contain),
  AnnotationLayer(controller: annot, contentSize: frameSize),
])
```

`frameSize` must be the real frame size so the `contain` fit matches the renderer's:
- best: give the renderer a `cachedRenderer: rtc.RTCVideoRenderer()` you own, and on its `onResize` set
  `Size(videoWidth, videoHeight)` (it follows rotation / window resizes);
- fallback: `publication.dimensions` (remote) or the preset size the share started with (local, `preset.sizeFor`).
The layer is `IgnorePointer` outside draw mode: the share view's taps / double-taps keep working.

## 5. `controls.dart` / `live_control_bar.dart`: the Annotate action and the toolbar

- A `LiveControlAction` "Annotate" (`Icons.draw_rounded`, label `t('تعليق توضيحي', 'Annotate')`), visible when a
  screen share is on stage and `_annot.canDrawLocal`, wrapped in `ParentComponent(featureKey: 'live.annotation')`.
  Its tap: `_annotOpen = !_annotOpen; _annot.setDrawMode(_annotOpen)` (Android whole-screen share: step 6).
- While `_annotOpen`: put `AnnotationControllerToolbar(controller: _annot, onClose: () => setState(() =>
  _annotOpen = false))` in the stage Stack, `PositionedDirectional(top: 12, start: 12, end: 12)` inside a `Center`
  (it is compact under 600 px and scrolls sideways; never wider than the stage). Keep the control bar visible
  while drawing (don't auto-hide it on phones), and close the toolbar when the room is minimised (`LiveRoomHost`).
- Students: listen to `_annot` and when `canDrawLocal` turns true / false show
  `showAppNotice(t('يمكنك الآن الرسم على الشاشة المشتركة', 'You can now draw on the shared screen'))` /
  `t('أوقف المعلّم الرسم للطلاب', 'The teacher turned drawing off')`.
- The room's own key handler (`KeyEventResult` around line 863): leave P / H / E / L / 1–3 / Ctrl+Z / Esc to the
  toolbar while `_annotOpen` (the toolbar's `AnnotationShortcuts` handles them on web / desktop).

## 6. `room_screen_share.dart`: Android whole-screen share (burned in, D-079 / D-083) — wired

After the share is published (`_offerAnnotationOverlay`):

1. `if (!await AndroidAnnotationOverlay.isPermitted())`: explain once per room with `appConfirm` ("To draw over
   other apps while you share, allow NextBrain to "Display over other apps" in Settings, then come back here",
   button "Open Settings"), then `AndroidAnnotationOverlay.requestPermission()` opens the system page and answers
   when the presenter comes back (re-checked 0.3 s / 1 s later for slow app-ops). Refused: the in-app annotation
   on the share view stays (vectors), nothing more is asked in that room.
2. Granted: `AndroidAnnotationOverlay.show(…)` ARMS the overlay for this share and the room's controller goes into
   burned-in mode (`annotationOverlayActive` → `_annot.setBurnedIn(true)`: nothing is sent as vectors, students
   cannot draw). A one-time notice says where to find it: "To draw over any screen: leave the app and tap the
   floating pen bubble".
3. Native (`AnnotationOverlayChannel` + `AnnotationOverlay.kt`): an armed overlay shows NOTHING while NextBrain is in
   front. When the activity stops (home, another app, recents) or goes into picture-in-picture, a 56 dp pen bubble
   appears over every app (draggable, snaps to the nearest side, remembers its place). Tap → a compact toolbar
   (pen · highlighter · eraser · laser · use apps / colour · thickness · undo · clear · hide tools · close) and a
   transparent full-screen canvas over the app below. "Use apps" and "Hide tools" keep the drawings on screen and
   let the touches through (canvas `FLAG_NOT_TOUCHABLE`, alpha ≤ the system's obscuring limit); "Close" clears
   them. Back in NextBrain every window goes; the drawings are kept and come back when the presenter leaves again.
   A rotation clears them (they marked content that moved). MediaProjection captures the overlay: the strokes are in
   the shared video and every recording.
4. `AndroidAnnotationOverlay.onClosed` → burned-in off: only when the overlay can no longer be shown (the permission
   was revoked while sharing). The room then falls back to in-app annotation.
5. Every stop (`_stopScreenShareAndroid`, the system's Stop → `shareStopped`, leaving the room) hides it; natively
   `ScreenCaptureService.stopShare` / `safeReleaseMedia` also call `AnnotationOverlayChannel.onShareStopped()`, so
   the bubble never outlives the share even if Dart is not running.

### The presenter's own window (black NextBrain area in the share)

MediaProjection draws a `FLAG_SECURE` window black (Android 15+: also a window with sensitive content). The app sets
`FLAG_SECURE` for the course video player and the exam screens. Protection now has one owner,
`lib/core/screen_security.dart` (`ScreenSecurity.protect(owner)` / `release(owner)`); the share calls
`beginShare()` / `endShare()`: on Android `ShareWindowGuard.kt` (channel `…/share_window`, registered by
`AnnotationOverlayChannel.register`) clears an OWNERLESS `FLAG_SECURE`, sets the Flutter view
`CONTENT_SENSITIVITY_NOT_SENSITIVE` (API 35+), logs what it found (`ShareWindowGuard: share window: FLAG_SECURE was
…, content sensitivity was …` — the evidence on a device), and restores exactly what it changed when the share ends.
On iOS an ownerless screen_protector layer is lifted for the broadcast and put back after. An open protected screen
(a course video, an exam) keeps its protection during a share: its area stays black on purpose.

### iOS and web: no drawing outside the app

iOS cannot draw over other apps: the broadcast upload extension (ReplayKit) has no UI and no window above other
apps, and iOS has no "Display over other apps" permission. While an iOS presenter shares the whole screen, the
annotation is drawn on the in-app view of the share (step 4 on the local share track) and travels as vectors to the
viewers: it is NOT in the broadcast frames and not on the presenter's other apps. A browser cannot draw over another
tab or window either: same in-app path. Both are solid paths (the same ink, the same controller); only Android burns
in.

### Ink (D-083)

Every pointer sample goes through `AnnotInkFilter` (annotation_ink.dart; Kotlin: `AnnotationInk.Filter`) before it is
drawn or sent: 2-D One Euro on the position, averaged and step-limited pressure, near-duplicates dropped, the real
last point added on lift. The painter draws the midpoint chain of quadratic Béziers; a stylus stroke (`pr: 1`) is one
filled shape with pressure width and tapered ends, cached piece by piece so nothing already drawn moves; finger /
mouse strokes are constant width; the highlighter is one translucent path. x / y travel with 5 decimals.

## 7. Backend / catalog (same change set)

- Kill switch `live.annotation` in `../back/services/feature_catalog.py`, then regenerate
  `test/contract/feature_keys.json` (`export_api_paths.py --front ../nextbrain-front`).
- Features guide entry in `../back/data/app_features_guide.json` (group live, roles teacher + student, ar + en,
  steps: Share → Annotate → tools; "Allow students to draw"; Android: "Display over other apps").
- No server route: annotation is peer-to-peer over the room's data channel. The LiveKit token must allow
  `canPublishData` for students (already true for hands / chat / reactions).

## Keyboard (web / desktop, while the toolbar is open)

P pen · H highlighter · E eraser · L laser · 1 / 2 / 3 thickness · Ctrl+Z / ⌘Z undo · Esc close. Keys typed into a
text field (chat, Q&A) are never taken.
