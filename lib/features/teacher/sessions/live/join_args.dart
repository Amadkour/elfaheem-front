// lib/features/teacher/sessions/live/join_args.dart
//
// What the pre-join page and the room need to join one live room. It lives apart from prejoin.dart (LiveKit, the
// room, the whiteboard ...) so the eager code that BUILDS the arguments (course page, calendar, go-live sheet)
// does not drag the room into main.dart.js: PreJoinPage itself is a deferred library (core/routing/deferred_screens.dart).
import '../../../../core/api_client.dart';
import '../../../shared/live/live_room.dart' show JoinOutcome, LiveRoomRef;

// ─────────────────────────────────────────────────────────────────────────────
// JoinArgs
// ─────────────────────────────────────────────────────────────────────────────
class JoinArgs {
  JoinArgs({
    this.e2ee = false,
    this.e2eeKey,
    this.simulcast = true,
    this.adaptiveStream = true,
    this.dynacast = true,
    this.preferredCodec = 'VP8',
    this.enableBackupVideoCodec = true,
    required this.sessionId,
    required this.courseId,
    this.maxStudents,
    required this.isTeacher,
    required this.userName,
    required this.userId,
    required this.onStart,
    required this.onEnd,
    this.onComplete,
    this.sessionName,
    // ── NEW: ApiClient passed through so RoomPage can upload chunks ──────────
    required this.apiClient,
    this.guest = false,
    this.canPublish = true,
    this.roomRef,
    this.isHost,
    this.onPoll,
    this.canRecord = false,
    @Deprecated('D-106: the pre-join page always waits for Join; the value is ignored') this.autoJoin = false,
    this.startsAt,
    this.hostName,
  });

  /// Was "press Join by itself once the devices are ready" (Meet now, Go live, Live now, a direct guest link).
  /// D-106: the pre-join page ALWAYS waits for the person to press Join — the value is kept for source
  /// compatibility and ignored. A 202 `waiting` after Join still follows the lobby by itself.
  @Deprecated('D-106: the pre-join page always waits for Join; the value is ignored')
  final bool autoJoin;

  /// The meeting's scheduled start (UTC), shown in the room's info sheet.
  final DateTime? startsAt;

  /// Who hosts the room, shown in the room's info sheet.
  final String? hostName;

  /// [meeting-recording] The creator of a calendar meeting may record it to a cloud drive (RoomPage.canRecord).
  final bool canRecord;

  /// True for a visitor who came through a public guest link: no account, no token.
  /// The room then skips every authenticated call (attendance, quizzes, participants…).
  final bool guest;

  /// Which live room this is (course session or calendar meeting, docs/backend/live-rooms-spec.md §1).
  /// Null → `LiveRoomRef.fromSessionId(sessionId)` (a meeting room keeps the `-meetingId` convention).
  final LiveRoomRef? roomRef;

  /// Who runs the lobby (share link, admission). Null → `isTeacher && !guest`; a meeting owner passes true
  /// without being a "teacher" (no recorder, no course-session calls).
  final bool? isHost;

  /// Polls a waiting lobby request (`onStart` answered `JoinOutcome.waiting`). Null → [LiveRoomApi.poll],
  /// which picks the public poll when the outcome carries a secret and the member poll otherwise.
  final Future<JoinOutcome> Function(JoinOutcome waiting)? onPoll;

  LiveRoomRef get ref => roomRef ?? LiveRoomRef.fromSessionId(sessionId ?? 0);

  /// Hosts get the host camera cap and never start with the camera off by the participants' default (D-090).
  bool get hostRole => isHost ?? (isTeacher && !guest);

  /// False → the participant may only watch and listen: the pre-join screen creates no
  /// microphone / camera tracks and the room shows only Leave, reactions and audio output.
  final bool canPublish;

  late final int? sessionId;
  final int courseId;
  final int? maxStudents;
  final bool e2ee;
  final bool isTeacher;
  final String userName;
  final int userId;
  final String? e2eeKey;
  final bool simulcast;
  final bool adaptiveStream;
  final bool dynacast;
  final String preferredCodec;
  final bool enableBackupVideoCodec;

  /// Optional session / meeting name shown on the pre-join screen
  /// (falls back to the generic "Live session").
  final String? sessionName;

  /// For teachers:  calls POST /live-sessions/start  → returns LiveResponseModel
  /// For students:  calls GET  /live-sessions/{id}/join → returns LiveResponseModel, or a [JoinOutcome]:
  /// `waiting` shows "Waiting for the host…" and polls until admitted (then the room opens), `admitted`
  /// carries the join payload, rejected / expired send the person back.
  final Future<dynamic> Function() onStart;

  /// Called when the session ends (teacher taps End, or room disconnects).
  final Future<dynamic> Function() onEnd;

  /// Called after a student leaves the room. Triggers POST /sessions/{id}/complete.
  final Future<void> Function()? onComplete;

  /// ApiClient instance scoped to the authenticated user.
  /// Passed down to RoomPage → _ClientRecorder for chunk upload auth.
  final ApiClient apiClient;

  /// The same join again after a lost connection (D9): the session the room ran (a quick session created on
  /// the first join keeps its id). The pre-join page opens with the room's mic / camera choices and waits for
  /// Join like every other entry (D-106).
  JoinArgs forRejoin({required int sessionId}) => JoinArgs(
        e2ee: e2ee,
        e2eeKey: e2eeKey,
        simulcast: simulcast,
        adaptiveStream: adaptiveStream,
        dynacast: dynacast,
        preferredCodec: preferredCodec,
        enableBackupVideoCodec: enableBackupVideoCodec,
        sessionId: sessionId,
        courseId: courseId,
        maxStudents: maxStudents,
        isTeacher: isTeacher,
        userName: userName,
        userId: userId,
        onStart: onStart,
        onEnd: onEnd,
        onComplete: onComplete,
        sessionName: sessionName,
        apiClient: apiClient,
        guest: guest,
        canPublish: canPublish,
        roomRef: roomRef,
        isHost: isHost,
        onPoll: onPoll,
        canRecord: canRecord,
        startsAt: startsAt,
        hostName: hostName,
      );
}
