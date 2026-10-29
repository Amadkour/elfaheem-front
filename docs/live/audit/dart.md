# Live audit: shared Dart room code (2026-10-29, read-only agent report; D1, D12 re-verified by hand)

livekit_client ^2.8.0 → 2.13.1 locked; flutter_webrtc fork ref 1634692. Paths under `lib/features/teacher/sessions/live/` unless shown.

| id | sev | file:line | issue | proposed fix |
|---|---|---|---|---|
| D1 | high ✔ | room.dart:1036, :244/:301 | pre-join mic OFF ignored: `enableAudio` never read; `_enableHdAudio` setMicrophoneEnabled(true) for every publisher — mic goes live on entry | gate on widget.enableAudio |
| D2 | high | room.dart:220; room_screen_share.dart:522, 593 | HD / iOS no-AEC options never applied: setSourceEnabled on an existing publication only unmutes (SDK local.dart:832-839) | restartTrack(options) or build the pre-join track with them |
| D3 | high | room.dart:1104-1148 | dispose never stops an iOS broadcast (only banner button): ReplayKit keeps capturing after leave | stopIOSBroadcast + disposeBroadcastSub in dispose |
| D4 | high (unverified) | room_screen_share.dart:513 | iOS setScreenShareEnabled → BroadcastManager.requestActivation (2nd picker) and publishes only when isBroadcasting; Info.plist lacks RTCScreenSharingExtension / RTCAppGroupIdentifier, SampleHandler has no flutter_webrtc socket uploader → viewers likely get no iOS share | wire extension to flutter_webrtc broadcast socket + plist keys; one picker |
| D5 | high | room_screen_share.dart:211-246 | Android share is video only; screenShareAudio republish loop is dead code (= A-audit) | native AudioPlaybackCapture → screenShareAudio track |
| D6 | high | room_screen_share.dart:333-385 | Web asks getDisplayMedia audio:true but never publishes the tab audio | publish getAudioTracks().first as screenShareAudio |
| D7 | high | room_screen_share.dart:181 | Android projection only when recorder != null (= A3) | projection whenever sharing |
| D8 | high | room.dart (no lifecycle code) | no AppLifecycleState handling; no mic FGS in background on Android (flutter_background unused); camera not muted in background (frozen frame) | AppLifecycleListener: camera off on pause, restore on resume; mic FGS while in a room |
| D9 | high | room.dart:1577-1607 | every non-server/non-client disconnect (reconnectAttemptsExceeded, signalingConnectionFailure, duplicateIdentity…) shows _ConnectionLostDialog and leaves; no Rejoin; no duplicateIdentity text | Rejoin action re-running connect; "opened on another device" text |
| D10 | medium | prejoin.dart:443-541 | Room + listener not disposed when connect fails; no initial-connect retry | dispose in catch; 1–2 retries with backoff |
| D11 | medium | prejoin.dart:434-440 | quickSession null → toast then LateInitializationError on localSessionId → second error dialog | return after the toast |
| D12 | high ✔ | prejoin.dart:503, 533; local_debug_save.dart | TEMP diagnostic LocalDebugSave ships: stop in onEnd, START after the room closes (reversed); saves a recording to Photos | remove both calls (+ native methods) |
| D13 | medium | prejoin.dart:387-390, 426-429, 452-456 | every publisher incl. students sends camera 1080p60 5 Mbps VP8, default simulcast | students 720p30 ~1.7 Mbps; explicit videoSimulcastLayers h180/h360 |
| D14 | medium | prejoin.dart:459-462; room_screen_share.dart:333 | screen-share settings contradict (H1080FPS15 vs maxFrameRate 30 vs encoding 30; web forces 1280x720); VP8 weak for text | one preset per mode (detail 1080p 5–15 fps ~2.5 Mbps / motion 720p30) |
| D15 | low | prejoin.dart:447-451 | mic 128 kbps dtx:false red:true for everyone | dtx on for speech; music mode for teacher only |
| D16 | medium | room_screen_share.dart:168-171 | starting a share on Android silently unmutes a muted mic | leave mic state alone |
| D17 | medium | room_screen_share.dart:335-385 | web "Stop sharing" button: SDK unpublishes but app refs + recorder attachment stay | listen TrackEnded / LocalTrackUnpublished, clean up |
| D18 | medium (unverified) | room_screen_share.dart:86-95 | manual share tracks tracked by stored sid; after full reconnect sid changes | look up by source |
| D19 | medium | widgets/controls.dart:445; calendar_meeting.dart:998 | share only when isTeacher; meetings pass isTeacher:false → nobody (not even owner) can share in a meeting; student block UI-only | isTeacher \|\| isHost; server canPublishSources (= L1) |
| D20 | medium | room.dart:1019-1020, 1116-1121 | meetings run course calls: /courses/0/students, /courses/0/exams/active polling, /live-sessions/-id/leave | skip when roomRef.kind == meeting |
| D21 | medium | room.dart:1609-1613, 1898, 1923-1935 | sort + full-page setState on every participant event / audio level; inconsistent comparator; tiles reorder constantly | throttle ~500 ms, stable sort with hysteresis, drop duplicate listener |
| D22 | medium | room.dart:1677-1700 | data packet with no / unknown topic opens showDataReceivedDialog on everyone's screen (spam) | ignore unknown topics |
| D23 | low | widgets/live_hands.dart:122 | hand packets trust payload identity / name: anyone can raise / lower anyone's hand | use senderIdentity; "lower other" only from hosts |
| D24 | low | room.dart:1663-1667 | TrackUnsubscribedEvent vs local sid: dead code | remove |
| D25 | low | room.dart:1617-1621 | every recording-status change opens a dialog for all | notice / pill |
| D26 | low | widgets/controls.dart:141 | enumerateDevices().then(setState) after dispose | mounted check |
| D27 | low | room.dart:956-1004; live_room_host.dart:~252 | aurora / glow loops run while minimized, no syncMotionLoop | TickerMode off when minimized; syncMotionLoop |
| D28 | low | room.dart:1166-1175 | hang up from mini box disconnects twice | drop the second |
| D29 | low | prejoin.dart:530-534 | canPublish fixed at join; allow-speak guest keeps listen-only bar | ParticipantPermissionsUpdatedEvent |

Fine: adaptiveStream / dynacast / simulcast on, backup codec on, e2ee off; reconnecting / reconnected notices; network change + token refresh left to SDK; device-change refreshes menus; wakelock on / off. No guard against two presenters (first screen track takes the stage).

## Inventory
Chat (topic chat, ephemeral, no history), hand raise (queue, re-announced), quiz (packet → REST poll; no live polls), reactions (lossy), Q&A none, layout = share stage + thumbnails + "+N" (no speaker / grid switch), draggable self-view, in-app minimize box (no OS PiP), no browser fullscreen, per-tile connection quality + stats overlay, no audio-only fallback, teacher controls guests only (mute, allow-speak, kick, mute-all), lobby / share link / quick guest link, free-time pill, keyboard shortcuts M/V/S/R/H/C/E, guest join page. None: breakout rooms, live captions, annotation / whiteboard / laser.

## Tests
test/org: live_room, live_room_host, live_lobby_controller, live_time_limit, live_quiz, live_duration, live_events_client, live_events_soak, meeting_recording. test/ui: live_controls_layout, live_hands_chat_layout, live_participant_layout, live_reactions_layout, live_mini_layout, live_lobby_layout, live_room_notice, live_time_limit_layout, prejoin_layout, guest_live_layout, meeting_recording_layout. None exercises a real Room connect / reconnect / screen share.
