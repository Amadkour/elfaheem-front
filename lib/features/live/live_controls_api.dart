// lib/features/live/live_controls_api.dart
//
// The host's ("teacher") controls over a live room — the pure part and the API (live hardening L2). Contract:
// ../back/routers/live_controls_router.py + services/live_controls.py, FLUTTER_API_CHANGES.md "Host controls".
// The widgets are in live_participant_controls.dart; integration steps in docs/live/teacher_controls_wiring.md.
// Unit-tested in test/org/live_controls_api_test.dart (paths and bodies are built by static functions, so the test
// never needs ApiClient).
//
//   LivePublishSource        camera · microphone · screen_share · screen_share_audio (the wire names).
//   LivePublishPermissions   what one participant may publish now (LiveKit's ParticipantPermission as plain values)
//                            and the next permission set for "allow / revoke screen share", "allow microphone",
//                            "allow drawing" (a drawing needs `can_publish_data`).
//   LiveControlTarget        one participant as the host's sheet sees them (plain values).
//   liveHostActionsFor       which actions the host is offered for that participant: nothing for a non-host viewer,
//                            for themselves or for another host (the server answers 409 cannot_moderate_host).
//   LiveLockState            GET/PUT …/lock.
//   LiveControlsApi          one method per route; the static `…Path` / `…Body` builders are what it sends.
//   liveControlsErrorText    server code → bilingual text (t(ar, en), no translation.json edits);
//                            liveControlsError(e) adds the live-room codes, 423 / 429 by status and the fallback.
//
// Hosts: the course's teacher (`teacher_<id>`), the staff session_access allows on that session (an assistant who
// joins as `student_<id>`) and a meeting's owner (`meet_<id>`). Everyone else gets 403 not_host.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_room_words.dart';

/// Kill-switch keys (ParentComponent / AppConfig.disableList, ../back/services/feature_catalog.py).
const String kLiveTeacherControlsFeatureKey = 'live.teacher_controls';
const String kLiveRoomLockFeatureKey = 'live.room_lock';

/// The server caps host actions at 60 a minute per host (429 too_many_requests, Retry-After: 60).
const int kLiveControlsPerMinute = 60;

// ─────────────────────────────────────────────────────────────────────────────
// Publish sources and permissions
// ─────────────────────────────────────────────────────────────────────────────

enum LivePublishSource { camera, microphone, screenShare, screenShareAudio }

extension LivePublishSourceWire on LivePublishSource {
  /// The server's name (`can_publish_sources`, `source`).
  String get wire => switch (this) {
        LivePublishSource.camera => 'camera',
        LivePublishSource.microphone => 'microphone',
        LivePublishSource.screenShare => 'screen_share',
        LivePublishSource.screenShareAudio => 'screen_share_audio',
      };
}

/// A source name as the server, the LiveKit proto (`SCREEN_SHARE`) or the Dart SDK (`screenShareVideo`) writes it.
/// Null for anything else.
LivePublishSource? livePublishSourceFrom(dynamic raw) {
  final n = '${raw ?? ''}'.trim().toLowerCase().replaceAll('_', '');
  return switch (n) {
    'camera' => LivePublishSource.camera,
    'microphone' || 'mic' => LivePublishSource.microphone,
    'screenshare' || 'screensharevideo' => LivePublishSource.screenShare,
    'screenshareaudio' => LivePublishSource.screenShareAudio,
    _ => null,
  };
}

/// The order the server lists sources in; every body is sent in this order.
const List<LivePublishSource> kLiveSourceOrder = LivePublishSource.values;

const Set<LivePublishSource> kLiveScreenSources = {LivePublishSource.screenShare, LivePublishSource.screenShareAudio};

/// What a participant who is not a host may publish by default when the server sent no explicit list: the room's
/// client offers a non-host camera + microphone only for an empty list (live_room_rules.dart, liveAllowedControls).
const Set<LivePublishSource> kLiveDefaultMemberSources = {LivePublishSource.camera, LivePublishSource.microphone};

/// One participant's publish permission (LiveKit `ParticipantPermission`): [canPublish], the source list
/// ([sources], empty = "every source" in LiveKit's sense) and [canPublishData] (chat, hands, reactions, drawing).
class LivePublishPermissions {
  const LivePublishPermissions({this.canPublish = true, this.sources = const {}, this.canPublishData = true});

  /// From the SDK's values: the names of `permissions.canPublishSources` (any spelling livePublishSourceFrom reads).
  factory LivePublishPermissions.fromNames({required bool canPublish, required Iterable<dynamic> sources, bool canPublishData = true}) =>
      LivePublishPermissions(
        canPublish: canPublish,
        sources: {for (final s in sources) ?livePublishSourceFrom(s)},
        canPublishData: canPublishData,
      );

  /// The server's echo of `POST …/permissions` (`{can_publish_sources, can_publish_data}`); an empty list there
  /// means "nothing" (the server switches publishing off rather than send LiveKit an empty list).
  factory LivePublishPermissions.fromJson(Map<String, dynamic> j) {
    final raw = j['can_publish_sources'];
    final list = raw is List ? raw : const [];
    final sources = {for (final s in list) ?livePublishSourceFrom(s)};
    return LivePublishPermissions(
      canPublish: sources.isNotEmpty,
      sources: sources,
      canPublishData: j['can_publish_data'] != false,
    );
  }

  final bool canPublish;
  final Set<LivePublishSource> sources;
  final bool canPublishData;

  /// What a NON-host may actually use: nothing without canPublish; camera + microphone for an empty list (the
  /// room never offers a non-host Share on "every source"); else the list.
  Set<LivePublishSource> get effective {
    if (!canPublish) return const {};
    if (sources.isEmpty) return kLiveDefaultMemberSources;
    return sources;
  }

  bool allows(LivePublishSource s) => effective.contains(s);

  bool get mayShareScreen => allows(LivePublishSource.screenShare);

  bool get mayUseMic => allows(LivePublishSource.microphone);

  /// The same permission with screen share (+ its audio) allowed or taken away; the other sources stay.
  LivePublishPermissions withScreenShare(bool allow) => _with(allow ? effective.union(kLiveScreenSources) : effective.difference(kLiveScreenSources));

  /// The same permission with the microphone allowed or taken away.
  LivePublishPermissions withMicrophone(bool allow) {
    final next = {...effective};
    allow ? next.add(LivePublishSource.microphone) : next.remove(LivePublishSource.microphone);
    return _with(next);
  }

  /// Drawing needs data publishing; the sources stay as they are.
  LivePublishPermissions withData(bool allow) =>
      LivePublishPermissions(canPublish: canPublish, sources: sources, canPublishData: allow);

  LivePublishPermissions _with(Set<LivePublishSource> next) =>
      LivePublishPermissions(canPublish: next.isNotEmpty, sources: next, canPublishData: canPublishData);

  /// The wire list in the server's order (`[]` = may publish nothing).
  List<String> get wireSources => [
        for (final s in kLiveSourceOrder)
          if (effective.contains(s)) s.wire,
      ];

  @override
  bool operator ==(Object other) =>
      other is LivePublishPermissions &&
      other.canPublish == canPublish &&
      other.canPublishData == canPublishData &&
      other.effective.length == effective.length &&
      other.effective.containsAll(effective);

  @override
  int get hashCode => Object.hash(canPublish, canPublishData, Object.hashAllUnordered(effective));

  @override
  String toString() => 'LivePublishPermissions($wireSources, data: $canPublishData)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Who is a host, and what the host may do to whom
// ─────────────────────────────────────────────────────────────────────────────

/// Prefixes the server mints (../back/services/LiveKit_service.py): the course teacher, a student / staff member,
/// a meeting member, a share-link guest.
const String kLiveTeacherIdentityPrefix = 'teacher_';
const String kLiveStudentIdentityPrefix = 'student_';
const String kLiveMeetingIdentityPrefix = 'meet_';
const String kLiveGuestIdentityPrefix = 'guest:';

bool liveIsGuestIdentity(String identity) => identity.startsWith(kLiveGuestIdentityPrefix);

/// True when [identity] is a host the server refuses to moderate (409 cannot_moderate_host): the room's own host
/// identity ([hostIdentity], when known), and in a course session every `teacher_*`. [knownHosts] adds the identities
/// the app knows to be co-hosts (an assistant joining as `student_<id>`); the server lets a host act on them, the
/// app never offers it.
bool liveIdentityIsHost(String identity, LiveRoomKind kind, {String? hostIdentity, Set<String> knownHosts = const {}}) {
  if (identity.isEmpty) return false;
  if (hostIdentity != null && hostIdentity.isNotEmpty && identity == hostIdentity) return true;
  if (kind == LiveRoomKind.session && identity.startsWith(kLiveTeacherIdentityPrefix)) return true;
  return knownHosts.contains(identity);
}

/// One participant as the host's controls see them — plain values (the room maps a RemoteParticipant into it).
class LiveControlTarget {
  const LiveControlTarget({
    required this.identity,
    this.name = '',
    this.imageUrl,
    this.isHost = false,
    this.isSelf = false,
    this.micOn = false,
    this.cameraOn = false,
    this.screenSharing = false,
    this.permissions = const LivePublishPermissions(),
    this.drawingAllowed = false,
  });

  final String identity;
  final String name;
  final String? imageUrl;

  /// A host (liveIdentityIsHost): never offered an action.
  final bool isHost;

  /// The viewer themselves: never offered an action (a host does not remove or mute themselves here).
  final bool isSelf;
  final bool micOn;
  final bool cameraOn;
  final bool screenSharing;
  final LivePublishPermissions permissions;

  /// The annotation permission packet currently lets this participant draw.
  final bool drawingAllowed;

  bool get isGuest => liveIsGuestIdentity(identity);

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (isGuest) return t('زائر', 'Guest');
    return identity;
  }
}

/// One remote participant as plain values → the host sheet's [LiveControlTarget] (the room reads the SDK's
/// Participant and passes what it found: `permissions.canPublishSources` as proto names, the photo the tiles read
/// from the metadata). [localIdentity] is the viewer's own identity.
LiveControlTarget liveControlTargetFrom({
  required String identity,
  required String name,
  required LiveRoomKind kind,
  required String localIdentity,
  String? imageUrl,
  bool micOn = false,
  bool cameraOn = false,
  bool screenSharing = false,
  bool canPublish = true,
  Iterable<dynamic> sources = const [],
  bool canPublishData = true,
  bool drawingAllowed = false,
  Set<String> knownHosts = const {},
}) =>
    LiveControlTarget(
      identity: identity,
      name: name,
      imageUrl: imageUrl == null || imageUrl.trim().isEmpty ? null : imageUrl.trim(),
      isHost: liveIdentityIsHost(identity, kind, knownHosts: knownHosts),
      isSelf: identity.isNotEmpty && identity == localIdentity,
      micOn: micOn,
      cameraOn: cameraOn,
      screenSharing: screenSharing,
      permissions: LivePublishPermissions.fromNames(canPublish: canPublish, sources: sources, canPublishData: canPublishData),
      drawingAllowed: drawingAllowed,
    );

/// Whether the LiveKit [identity] / [name] is the enrolled student [studentId] / [studentName]: the server mints
/// `student_<id>` (older servers the bare id); the name is the last resort, as the roster always matched.
bool liveIdentityIsStudent(String identity, String name, {required int studentId, required String studentName}) {
  if (identity == '$kLiveStudentIdentityPrefix$studentId' || identity == '$studentId') return true;
  return studentName.trim().isNotEmpty && name.trim() == studentName.trim();
}

/// Everything a host can do to one participant, in the order the sheet lists them.
enum LiveHostAction {
  muteMic,
  allowMic,
  stopCamera,
  stopScreenShare,
  allowScreenShare,
  revokeScreenShare,
  allowDrawing,
  revokeDrawing,
  remove,
}

/// Destructive actions are confirmed first (appConfirm).
bool liveHostActionIsDestructive(LiveHostAction a) => a == LiveHostAction.remove;

/// The actions offered for [target]. Empty when the viewer is not a host, for the viewer themselves and for another
/// host. [drawingAvailable]: the room has the annotation layer (otherwise the drawing toggle is hidden).
List<LiveHostAction> liveHostActionsFor(LiveControlTarget target, {required bool viewerIsHost, bool drawingAvailable = false}) {
  if (!viewerIsHost || target.isSelf || target.isHost || target.identity.isEmpty) return const [];
  final p = target.permissions;
  return [
    if (target.micOn) LiveHostAction.muteMic,
    if (!p.mayUseMic) LiveHostAction.allowMic,
    if (target.cameraOn) LiveHostAction.stopCamera,
    if (target.screenSharing) LiveHostAction.stopScreenShare,
    if (p.mayShareScreen) LiveHostAction.revokeScreenShare else LiveHostAction.allowScreenShare,
    if (drawingAvailable) (target.drawingAllowed && p.canPublishData) ? LiveHostAction.revokeDrawing : LiveHostAction.allowDrawing,
    LiveHostAction.remove,
  ];
}

/// The permission to POST for a permission action; null for an action that is not a permission change
/// (mute / stop / remove) and for "revoke drawing", which only sends the annotation packet: data publishing stays,
/// because chat, raised hands and reactions ride on it. "Allow drawing" sends one only when data is switched off.
LivePublishPermissions? livePermissionsFor(LiveHostAction action, LivePublishPermissions current) => switch (action) {
      LiveHostAction.allowScreenShare => current.withScreenShare(true),
      LiveHostAction.revokeScreenShare => current.withScreenShare(false),
      LiveHostAction.allowMic => current.withMicrophone(true),
      LiveHostAction.allowDrawing => current.canPublishData ? null : current.withData(true),
      _ => null,
    };

/// The source a "mute" action sends (`POST …/mute {source}`); null for the other actions.
LivePublishSource? liveMuteSourceFor(LiveHostAction action) => switch (action) {
      LiveHostAction.muteMic => LivePublishSource.microphone,
      LiveHostAction.stopCamera => LivePublishSource.camera,
      LiveHostAction.stopScreenShare => LivePublishSource.screenShare,
      _ => null,
    };

/// Bilingual label of an action (the sheet's rows, Semantics).
String liveHostActionLabel(LiveHostAction a) => switch (a) {
      LiveHostAction.muteMic => t('كتم الميكروفون', 'Mute microphone'),
      LiveHostAction.allowMic => t('السماح بالميكروفون', 'Allow microphone'),
      LiveHostAction.stopCamera => t('إيقاف الكاميرا', 'Stop camera'),
      LiveHostAction.stopScreenShare => t('إيقاف مشاركة الشاشة', 'Stop screen share'),
      LiveHostAction.allowScreenShare => t('السماح بمشاركة الشاشة', 'Allow screen share'),
      LiveHostAction.revokeScreenShare => t('منع مشاركة الشاشة', 'Revoke screen share'),
      LiveHostAction.allowDrawing => t('السماح بالرسم على الشاشة', 'Allow drawing'),
      LiveHostAction.revokeDrawing => t('منع الرسم على الشاشة', 'Revoke drawing'),
      LiveHostAction.remove => t('إخراج من الغرفة', 'Remove from room'),
    };

/// The notice after an action succeeded.
String liveHostActionDone(LiveHostAction a, String name) => switch (a) {
      LiveHostAction.muteMic => t('تم كتم ميكروفون $name', '$name was muted'),
      LiveHostAction.allowMic => t('يمكن لـ $name التحدث الآن', '$name may speak now'),
      LiveHostAction.stopCamera => t('تم إيقاف كاميرا $name', "$name's camera was stopped"),
      LiveHostAction.stopScreenShare => t('تم إيقاف مشاركة شاشة $name', "$name's screen share was stopped"),
      LiveHostAction.allowScreenShare => t('يمكن لـ $name مشاركة شاشته الآن', '$name may share their screen now'),
      LiveHostAction.revokeScreenShare => t('لم يعد بإمكان $name مشاركة الشاشة', '$name can no longer share their screen'),
      LiveHostAction.allowDrawing => t('يمكن لـ $name الرسم الآن', '$name may draw now'),
      LiveHostAction.revokeDrawing => t('لم يعد بإمكان $name الرسم', '$name can no longer draw'),
      LiveHostAction.remove => t('تم إخراج $name من الغرفة', '$name was removed from the room'),
    };

/// The confirmation of a destructive action ([kind]: the open room by default, D-106).
String liveHostActionConfirm(LiveHostAction a, String name, {LiveRoomKind? kind}) => switch (a) {
      LiveHostAction.remove => liveT(kind,
          ar: 'إخراج $name من الغرفة؟ لن يتمكن من العودة إلى هذه الجلسة.',
          en: 'Remove $name from the room? They cannot come back to this session.',
          meetingAr: 'إخراج $name من الغرفة؟ لن يتمكن من العودة إلى هذا الاجتماع.',
          meetingEn: 'Remove $name from the room? They cannot come back to this meeting.'),
      _ => liveHostActionLabel(a),
    };

// ─────────────────────────────────────────────────────────────────────────────
// Lock
// ─────────────────────────────────────────────────────────────────────────────

/// `GET|PUT …/lock` → `{kind, id, locked, locked_at, locked_by}`.
class LiveLockState {
  const LiveLockState({required this.locked, this.lockedAt, this.lockedBy});

  factory LiveLockState.fromJson(Map<String, dynamic> j) => LiveLockState(
        locked: j['locked'] == true,
        lockedAt: _utc(j['locked_at']),
        lockedBy: int.tryParse('${j['locked_by'] ?? ''}'),
      );

  static const unlocked = LiveLockState(locked: false);

  final bool locked;
  final DateTime? lockedAt;
  final int? lockedBy;

  /// The server writes naive UTC.
  static DateTime? _utc(dynamic v) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty) return null;
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error text
// ─────────────────────────────────────────────────────────────────────────────

/// Bilingual text for the host-control codes; null for a code this file does not know. [kind]: the room's kind
/// (default: the open room) — a meeting says «الاجتماع» (D-106).
String? liveControlsErrorText(String? code, {LiveRoomKind? kind}) => switch (code) {
      'not_host' || 'host_only' => t('هذا الإجراء لمضيف الغرفة فقط.', 'Only the room host can do this.'),
      'live_not_started' => t('لم يبدأ البث بعد أو انتهى.', 'The room is not live right now.'),
      'cannot_moderate_host' => t('لا يمكن تطبيق هذا الإجراء على مضيف الغرفة.', 'This cannot be done to a host of the room.'),
      'bad_source' => t('نوع الوسائط غير معروف.', 'Unknown media type.'),
      'too_many_requests' => t('إجراءات كثيرة في وقت قصير — انتظر دقيقة ثم أعد المحاولة.', 'Too many actions — wait a minute and try again.'),
      'livekit_error' => t('تعذر تنفيذ الإجراء على خادم البث. أعد المحاولة.', 'The live server could not do this. Try again.'),
      'room_locked' => t('الغرفة مقفلة: لا يمكن لأحد جديد الانضمام الآن.', 'The room is locked: nobody new can join right now.'),
      'participant_removed' => liveT(kind,
          ar: 'أخرجك المضيف من هذه الجلسة.',
          en: 'The host removed you from this session.',
          meetingAr: 'أخرجك المضيف من هذا الاجتماع.',
          meetingEn: 'The host removed you from this meeting.'),
      'guest_blocked' => t('لا يمكنك الانضمام إلى هذه الغرفة.', 'You cannot join this room.'),
      _ => null,
    };

/// The text for a join the host's controls refused — 423 `room_locked`, 403 `participant_removed` /
/// `guest_blocked` — or null for any other failure (the caller shows its own text). Never retried: a 4xx.
String? liveJoinRefusalText(Object e, {LiveRoomKind? kind}) {
  final ex = ApiException.from(e);
  switch (ex.code) {
    case 'room_locked' || 'participant_removed' || 'guest_blocked':
      return liveControlsErrorText(ex.code, kind: kind);
  }
  if (ex.statusCode == 423) return liveControlsErrorText('room_locked');
  return null;
}

/// The text to show for a failed host action: the codes above, then the live-room codes, then 423 / 429 by status,
/// then ApiException's own (already user-safe) message.
String liveControlsError(Object e) {
  final ex = ApiException.from(e);
  final text = liveControlsErrorText(ex.code) ?? liveRoomCodeText(ex.code);
  if (text != null) return text;
  if (ex.statusCode == 423) return liveControlsErrorText('room_locked')!;
  if (ex.statusCode == 429) return liveControlsErrorText('too_many_requests')!;
  if (ex.statusCode == 403) return liveControlsErrorText('not_host')!;
  return ex.message;
}

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

/// The host's calls on one room. Every path is written out (static builders) so the API contract scan can read it
/// and the unit test can check it without ApiClient.
class LiveControlsApi {
  LiveControlsApi(this.ref, {ApiClient? api}) : _api = api ?? ApiClient();

  final LiveRoomRef ref;
  final ApiClient _api;

  Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  // ── Paths ─────────────────────────────────────────────────────────────────

  static String mutePath(LiveRoomRef r, String identity) =>
      '/api/v1/live/${r.kindName}/${r.id}/participants/${Uri.encodeComponent(identity)}/mute';

  static String removePath(LiveRoomRef r, String identity) =>
      '/api/v1/live/${r.kindName}/${r.id}/participants/${Uri.encodeComponent(identity)}/remove';

  static String permissionsPath(LiveRoomRef r, String identity) =>
      '/api/v1/live/${r.kindName}/${r.id}/participants/${Uri.encodeComponent(identity)}/permissions';

  static String muteAllPath(LiveRoomRef r) => '/api/v1/live/${r.kindName}/${r.id}/mute-all';

  static String lockPath(LiveRoomRef r) => '/api/v1/live/${r.kindName}/${r.id}/lock';

  static String endForAllPath(LiveRoomRef r) => '/api/v1/live/${r.kindName}/${r.id}/end-for-all';

  /// WP1 (D-1950): the host's roster, hidden people included (the LiveKit participant list no longer shows them).
  static String peoplePath(LiveRoomRef r) => '/api/v1/live/${r.kindName}/${r.id}/people';

  /// WP1: bring a hidden person on stage / take them off.
  static String stagePath(LiveRoomRef r, String identity) =>
      '/api/v1/live/${r.kindName}/${r.id}/participants/${Uri.encodeComponent(identity)}/stage';

  // ── Bodies ────────────────────────────────────────────────────────────────

  /// One track by sid, else every track of [source] (the server's default is the microphone).
  static Map<String, dynamic> muteBody({String? trackSid, LivePublishSource? source}) => {
        if (trackSid != null && trackSid.isNotEmpty) 'track_sid': trackSid,
        if ((trackSid == null || trackSid.isEmpty) && source != null) 'source': source.wire,
      };

  static Map<String, dynamic> permissionsBody(LivePublishPermissions p) => {
        'can_publish_sources': p.wireSources,
        'can_publish_data': p.canPublishData,
      };

  static Map<String, dynamic> muteAllBody({bool allowUnmute = true}) => {'allow_unmute': allowUnmute};

  static Map<String, dynamic> lockBody(bool locked) => {'locked': locked};

  static Map<String, dynamic> stageBody(bool on) => {'on': on};

  // ── Calls ─────────────────────────────────────────────────────────────────

  /// How many tracks were muted (0 = it was already muted).
  Future<int> mute(String identity, {String? trackSid, LivePublishSource? source}) async {
    final r = _map(await _api.post(mutePath(ref, identity), body: muteBody(trackSid: trackSid, source: source)));
    return int.tryParse('${r['muted'] ?? 0}') ?? 0;
  }

  /// Disconnects the participant and blocks the identity for this room (one session run / one meeting room).
  Future<bool> remove(String identity) async {
    final r = _map(await _api.post(removePath(ref, identity)));
    return r['removed'] != false;
  }

  /// The permission the server applied (echoed).
  Future<LivePublishPermissions> setPermissions(String identity, LivePublishPermissions p) async =>
      LivePublishPermissions.fromJson(_map(await _api.post(permissionsPath(ref, identity), body: permissionsBody(p))));

  /// Mutes everyone but the hosts; [allowUnmute] false also takes their microphone away. Returns how many.
  Future<int> muteAll({bool allowUnmute = true}) async {
    final r = _map(await _api.post(muteAllPath(ref), body: muteAllBody(allowUnmute: allowUnmute)));
    return int.tryParse('${r['muted'] ?? 0}') ?? 0;
  }

  Future<LiveLockState> lock() async => LiveLockState.fromJson(_map(await _api.get(lockPath(ref))));

  Future<LiveLockState> setLock(bool locked) async =>
      LiveLockState.fromJson(_map(await _api.put(lockPath(ref), body: lockBody(locked))));

  /// WP1: everyone in the room as the host sees them (`GET …/people`): raw rows, parsed by LivePeopleController.
  Future<List<Map<String, dynamic>>> people() async {
    final r = _map(await _api.get(peoplePath(ref)));
    final items = r['items'];
    return [
      if (items is List)
        for (final i in items)
          if (i is Map) Map<String, dynamic>.from(i),
    ];
  }

  /// WP1: on stage = visible with camera and microphone, off = hidden again. The identity's `on_stage` as applied.
  Future<bool> stage(String identity, bool on) async {
    final r = _map(await _api.post(stagePath(ref, identity), body: stageBody(on)));
    return r['on_stage'] == true;
  }

  /// Ends the room and disconnects everyone at once. Returns how many were removed.
  Future<int> endForAll() async {
    final r = _map(await _api.post(endForAllPath(ref)));
    return int.tryParse('${r['removed'] ?? 0}') ?? 0;
  }
}
