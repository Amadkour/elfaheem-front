# Host ("teacher") controls — wiring into the room

Status (2026-10-29): steps 1–4 and 7 are **applied** (room.dart "Host controls" region, prejoin.dart, and
`_onJoinLiveAsStudent` in sessions_provider.dart, which no longer swallows a refused join). Step 5's lock indicator and
step 6 (drawing) are still open; the drawing hooks stay null / false until the annotation layer lands.

What the room does beyond the steps below:
- **End for everyone → "the host ended the session"** for the people the server removes. A course session's
  end-for-all removes every participant (`DisconnectReason.participantRemoved`, the same reason a single Remove gives;
  a meeting's room is deleted → `roomDeleted`, already "session ended"). The host's controller calls
  `onEndForAllPhase(true)` right before the request and `(false)` when it failed; the room publishes a reliable packet
  on topic `room_end` (`lib/features/shared/live/live_end_signal.dart`), every room keeps it in `LiveEndForAllSignal`,
  and `liveDisconnectActionAfterEndSignal` turns a removal within 5 minutes of "ending" into `sessionEnded`. No request
  at disconnect time; packets from guests are ignored.
- The host's own removal / deleted room after End for everyone shows no dialog (`_endedForAll`); the recorder is
  stopped and drained through `_endSessionWithRecording(serverEnded: true)` (no second `onEnd`), and `_leaveRoom()`
  runs once.
- Hosts also see "others in the room" (meeting members, staff, co-hosts: remote participants that are neither guests
  nor on the roster) with the same ⋮; the roster matches `student_<id>` identities (`liveIdentityIsStudent`).

New files (do not need edits):

- `lib/features/shared/live/live_controls_api.dart` — `LiveControlsApi(ref)` (one method per route), pure helpers
  (`liveHostActionsFor`, `livePermissionsFor`, `liveMuteSourceFor`, `liveIdentityIsHost`, `LivePublishPermissions`,
  `LiveControlTarget`, `LiveLockState`), `liveControlsErrorText(code)` / `liveControlsError(e)`, feature keys
  `kLiveTeacherControlsFeatureKey` (`live.teacher_controls`) and `kLiveRoomLockFeatureKey` (`live.room_lock`).
- `lib/features/shared/live/live_participant_controls.dart` — `LiveHostControlsController`, `showLiveParticipantControls`,
  `LiveParticipantActionsBody`, `LiveParticipantControlsButton`, `LiveHostControlsBar`, `LiveHostControlsHeader`.
- Tests: `test/org/live_controls_api_test.dart`, `test/ui/live_participant_controls_layout_test.dart`.

Backend contract: `../back/routers/live_controls_router.py`, `services/live_controls.py`, `FLUTTER_API_CHANGES.md`
("Live hardening, batch 2 — Host controls"). The routes are already in `test/contract/api_paths.json` and the keys in
`test/contract/feature_keys.json`.

## 1. room.dart — state (next to the "Lobby" region)

Add a region like the lobby's, the only host-controls code in this file:

```dart
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart';
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart';

// ── Host controls (live.teacher_controls / live.room_lock) ─────────────────
LiveHostControlsController? _controls;

bool get _canModerate => widget.host && !widget.isGuest;

void _startControls() {
  if (!_canModerate) return;
  final off = AppConfig.disableList;
  if (off.contains(kLiveTeacherControlsFeatureKey) && off.contains(kLiveRoomLockFeatureKey)) return;
  _controls = LiveHostControlsController(widget.ref,
      onDrawingChanged: null /* step 6: the annotation layer's permission packet */);
  if (!off.contains(kLiveRoomLockFeatureKey)) unawaited(_controls!.loadLock());
}
```

- Call `_startControls();` right after `_startLobby();` (the connected / init path).
- In `dispose()`: `_controls?.dispose();` next to `_lobby?.dispose();`.

## 2. room.dart — map a participant into a target

```dart
LiveControlTarget _controlTarget(RemoteParticipant p) {
  final perms = p.permissions;
  return LiveControlTarget(
    identity: p.identity,
    name: p.name,
    imageUrl: /* the same metadata.image_url the tiles read (widgets/participant.dart) */ null,
    isHost: liveIdentityIsHost(p.identity, widget.ref.kind),
    isSelf: p.identity == _myIdentity,
    micOn: p.isMicrophoneEnabled(),
    cameraOn: p.isCameraEnabled(),
    screenSharing: p.isScreenShareEnabled(),
    permissions: LivePublishPermissions.fromNames(
      canPublish: perms.canPublish,
      sources: [for (final s in perms.canPublishSources) s.name], // proto names: CAMERA, SCREEN_SHARE, …
      canPublishData: perms.canPublishData,
    ),
    drawingAllowed: /* step 6: the annotation layer's per-identity state */ false,
  );
}

Future<void> _openParticipantControls(RemoteParticipant p) async {
  final c = _controls;
  if (c == null) return;
  _pokeControls();
  await showLiveParticipantControls(context, controller: c, target: _controlTarget(p),
      drawingAvailable: /* step 6 */ false);
}
```

The sheet confirms Remove with `appConfirm`, shows every result with `showAppNotice` and closes after a success. The
target is a snapshot: LiveKit's own events (`TrackMutedEvent`, `ParticipantPermissionsUpdatedEvent`,
`ParticipantDisconnectedEvent`) already re-sort / rebuild the panel afterwards.

## 3. room.dart — the participants panel (`_buildParticipantPanel`)

a. **Host bar** — right below the header `Container` (before the "Teacher row" `_ParticipantRow`):

```dart
if (_controls != null)
  LiveHostControlsHeader(
    controller: _controls!,
    onEnded: _leaveRoom, // the server ended the room; leave like the host's own End
  ),
```

`LiveHostControlsHeader` hides Mute all / End for everyone under `live.teacher_controls` and the lock row under
`live.room_lock` by itself (ParentComponent). It is drawn on the dark panel (LivePalette) and fits the 300 px panel.
Keep the old header button "mute all guests" (`live_room.mute_all_guests`, `_guestsMuteAll`) only when
`_controls == null || AppConfig.disableList.contains(kLiveTeacherControlsFeatureKey)` — the new Mute all covers guests
too (everyone but the hosts).

b. **Per-participant ⋮** — the student list's `_ParticipantRow` (inside `ListView.builder`) gets a `trailing:` when
the participant is in the room:

```dart
trailing: (_controls != null && rp != null)
    ? AnimatedBuilder(
        animation: _controls!,
        builder: (_, _) => LiveParticipantControlsButton(
          name: s.name,
          busy: _controls!.busyFor(rp.identity) != null,
          onPressed: () => unawaited(_openParticipantControls(rp)),
        ),
      )
    : null,
```

For guests keep `_guestMenu(g)` as it is (its "allow speak" uses the session guest routes and also works for meetings
only through those routes). Optional: when `live.teacher_controls` is on, a guest row may use the same button —
`remove` blocks a guest by identity + address like the guest kick.

c. A remote participant who is not in `_enrolledStudents` (a meeting member, a staff member) gets no row today; if a
"Others in the room" list is added, give each row the same `trailing`.

## 4. room.dart — End for everyone vs End

`end-for-all` removes every participant at once (a session: the normal end + removal; a meeting: the room is
deleted). The existing End button (`_endSessionWithRecording`, `POST /live-sessions/{id}/end`) stays as it is. After
`onEnded` the host's own `RoomDisconnectedEvent` arrives with `roomDeleted` / `participantRemoved`: for the teacher
`liveDisconnectAction` already returns `none` on roomDeleted; make sure the `_leaveRoom()` from `onEnded` and the
disconnect handler do not both show a dialog (check `mounted` / a `_leaving` flag before showing the "removed" dialog).
If the room records on the device (client recorder), call the same stop / drain as `_endSessionWithRecording` before
`_leaveRoom()` — simplest: `onEnded: () => unawaited(_endSessionWithRecording())` when a recorder is running, else
`_leaveRoom`.

## 5. controls.dart / live_control_bar.dart

Nothing is required: the host's tools live in the participants panel. Optional: a "Lock" indicator on the top bar
while `_controls?.locked == true` (`Icons.lock_rounded`, `LivePalette.warning`, tooltip
`t('الغرفة مقفلة', 'Room locked')`) — wrap it in `ParentComponent(featureKey: kLiveRoomLockFeatureKey, …)`.

## 6. Drawing (annotation) permission

"Allow drawing" = `can_publish_data` on (the controller POSTs `…/permissions` only when data is off) **plus** the
annotation layer's permission packet; "Revoke drawing" = the packet only (data stays: chat, raised hands and reactions
ride on it). When the annotation layer lands:

- set `_controls!.onDrawingChanged = (identity, allow) => <annotation layer>.sendPermission(identity, allow);`
- pass `drawingAvailable: true` to `showLiveParticipantControls` and the layer's per-identity state as
  `LiveControlTarget.drawingAllowed`.

Until then the drawing row is hidden (`drawingAvailable: false`).

## 7. prejoin.dart / the join paths (other sessions' files)

Joins may now answer **423 `room_locked`** (a new non-host join while the room is locked) and **403
`participant_removed`** (removed from this run / room). Map them with `liveControlsErrorText(code)` where the pre-join
page turns join errors into text (before the generic `ApiException.from(e).message`), and do not retry them
(`liveConnectRetryDelay` already never retries a 4xx). A removed participant who is still connected gets
`DisconnectReason.participantRemoved` → the existing `LiveDisconnectAction.removed` dialog; its "Rejoin" would now hit
403 `participant_removed`, so the dialog should not offer Rejoin for `removed` (it already does not).

## 8. Feature guide

Add an entry to `../back/data/app_features_guide.json` ("Host controls in the live room": mute / stop camera / allow
or revoke screen share / remove / mute all / lock / end for everyone; place: live room → Participants; keys
`live.teacher_controls`, `live.room_lock`; roles teacher, org staff hosting a session, meeting owners).

## Assumptions

- `identity` in the path is URL-encoded (`guest:ab12` → `guest%3Aab12`); FastAPI decodes it.
- A non-host's empty `canPublishSources` is treated as camera + microphone (the room's own `liveAllowedControls`
  rule), so "Allow screen share" on such a participant sends `[camera, microphone, screen_share, screen_share_audio]`.
- `mute` sends `{source}` (never `track_sid` from the sheet); "Stop screen share" mutes `screen_share` (the server mutes
  its tracks; the student can share again only if still allowed — use "Revoke screen share" to stop for good).
- Mute all is sent with `allow_unmute: true` (people may unmute themselves); a host who wants to keep someone quiet
  uses the per-participant "Revoke" path (the sheet then offers "Allow microphone").
- Co-hosts (an assistant joining as `student_<id>`) cannot be recognised in the app without token metadata; they are
  offered actions, and the server lets a host act on them (only the host identity / `teacher_*` answer 409
  `cannot_moderate_host`, which the notice explains). Pass `knownHosts` to `liveIdentityIsHost` if the token ever
  carries a role.
- A bare 404 / 405 on `GET …/lock` (older server) hides the lock row; other errors leave it usable and the PUT tells.
