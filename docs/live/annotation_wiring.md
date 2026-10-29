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

## 6. `room_screen_share.dart`: Android whole-screen share (burned in)

In `_toggleScreenShareAndroid`, after the share is published, the Annotate action works differently for the
LOCAL presenter on Android:

1. `if (!await AndroidAnnotationOverlay.isPermitted())`: explain once with `appConfirm` (`t('للرسم فوق التطبيقات
   الأخرى أثناء المشاركة، اسمح بـ «الظهور فوق التطبيقات الأخرى»', 'To draw over other apps while you share, allow
   "Display over other apps"')`), then `await AndroidAnnotationOverlay.requestPermission()`.
2. Granted: `AndroidAnnotationOverlay.show(colors: [for (c in annotPresetColors(context.colors)) c.toARGB32()],
   color: _annot.colorArgb, thickness: _annot.thickness, surface: LivePalette.surfaceHi.toARGB32(), accent:
   LivePalette.accent.toARGB32())`; on true: `_annot.setBurnedIn(true)` (viewers: students cannot draw, nothing is
   sent as vectors), keep `_annotOpen = false` (the native toolbar replaces the in-app one).
3. Refused / `show` false: `showAppNotice(t('بدون الإذن ترسم داخل التطبيق فقط', 'Without it you draw inside the
   app only'))` and open the in-app toolbar (vectors, step 5) — the fallback D-079 names.
4. `AndroidAnnotationOverlay.onClosed = () { _annot.setBurnedIn(false); }` (set once in `initState`).
5. In `_stopScreenShareAndroid` (and the system's own Stop → `shareStopped`): `await AndroidAnnotationOverlay.hide();
   _annot.setBurnedIn(false);`.
iOS (ReplayKit) and web cannot draw over other apps / tabs: there the presenter annotates on the in-app view of
the share (step 4 on the local share track) and the strokes travel as vectors.

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
