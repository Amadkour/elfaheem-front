// lib/features/shared/live/live_room.dart
//
// Live rooms (course live sessions AND calendar meetings): share links and the admission lobby — the pure part.
// Contract: docs/backend/live-rooms-spec.md (sections 1–4). Everything here takes plain values and is unit-tested in
// test/org/live_room_test.dart; the sheets and screens are in live_lobby_sheets.dart.
//
//   LiveRoomRef(kind, id)   which room: `session` (sessions.id, host = the course teacher) or `meeting`
//                           (cal_meetings.id, host = the owner). The room screen keeps its `sessionId = -meetingId`
//                           convention (`sessionId` / `fromSessionId`).
//   LivePolicy              GET/PUT …/policy: member admission (open | approve), guest admission (approve | auto),
//                           the waiting count and the share link (LiveLink).
//   LobbyRequest            one person waiting (member or guest) — GET …/lobby.
//   JoinOutcome             what a join call answered: admitted (with the join payload) | waiting(requestId, secret?,
//                           pollAfter) | rejected | expired. ApiClient returns every 2xx body as-is (a 202 looks like
//                           a 200 — the status code is dropped by `_unwrap`), so the answer is told apart by its
//                           `status` field: `waiting` → lobby, anything else (or no status at all, today's member
//                           join payload) → admitted.
//   LiveRoomApi             the host's calls (policy, link, lobby) and the joiner's polls (auth + public) and the
//                           signed-in link join.
//   LiveLobbyEvents         the silent push `live_join_request` lands here (notification_service.dart); the room's
//                           lobby controller listens and refreshes at once.
//   liveRoomErrorText       server codes → bilingual text (t(ar, en), no translation.json edits).
library;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show t;
import '../../teacher/sessions/model/live_response_model.dart';

/// Kill-switch keys of the feature (ParentComponent / AppConfig.disableList).
const String kLiveLobbyFeatureKey = 'live.lobby';
const String kLiveShareLinkFeatureKey = 'live.share_link';

/// How often the host asks the lobby while the lobby sheet is shown (and the quick follow-up after a push).
const Duration kLobbyPollEvery = Duration(seconds: 4);

/// How often the host's room asks the lobby while the sheet is closed; the push and a resume refresh at once.
const Duration kLobbyPollIdle = Duration(seconds: 15);

/// A waiting request dies on the server after this long: the joiner's screen says so even if the poll never does.
const Duration kLobbyRequestLifetime = Duration(minutes: 10);

// ─────────────────────────────────────────────────────────────────────────────
// Room identity
// ─────────────────────────────────────────────────────────────────────────────

enum LiveRoomKind { session, meeting }

class LiveRoomRef {
  const LiveRoomRef(this.kind, this.id);

  const LiveRoomRef.session(int id) : this(LiveRoomKind.session, id);

  const LiveRoomRef.meeting(int id) : this(LiveRoomKind.meeting, id);

  final LiveRoomKind kind;
  final int id;

  bool get isMeeting => kind == LiveRoomKind.meeting;

  /// `session` | `meeting` — the `{kind}` of every `/api/v1/live/{kind}/{id}/…` route.
  String get kindName => kind.name;

  /// The room screen's `sessionId`: a meeting room is `-meetingId` (calendar_meeting.dart).
  int get sessionId => isMeeting ? -id : id;

  /// The inverse of [sessionId].
  static LiveRoomRef fromSessionId(int sessionId) =>
      sessionId < 0 ? LiveRoomRef.meeting(-sessionId) : LiveRoomRef.session(sessionId);

  /// From a push / notification payload (`kind` + `id`, every value may be a string). Null when either is missing.
  static LiveRoomRef? parse(dynamic kind, dynamic id) {
    final k = '${kind ?? ''}'.trim().toLowerCase();
    final n = int.tryParse('${id ?? ''}');
    if (n == null) return null;
    if (k == 'meeting' || k == 'cal_meeting' || k == 'meetings') return LiveRoomRef.meeting(n);
    if (k == 'session' || k == 'sessions' || k == 'live_session') return LiveRoomRef.session(n);
    return null;
  }

  String get basePath => '/api/v1/live/$kindName/$id';

  @override
  bool operator ==(Object other) => other is LiveRoomRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'LiveRoomRef($kindName, $id)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Policy and link
// ─────────────────────────────────────────────────────────────────────────────

/// Who may enter without the host's nod: members (`open`) or only after approval (`approve`).
enum LiveAdmission { open, approve }

/// Visitors from the share link: `approve` (default) or `auto`.
enum LiveGuestAdmission { approve, auto }

LiveAdmission liveAdmissionFrom(dynamic v) => '${v ?? ''}' == 'approve' ? LiveAdmission.approve : LiveAdmission.open;

LiveGuestAdmission liveGuestAdmissionFrom(dynamic v) =>
    '${v ?? ''}' == 'auto' ? LiveGuestAdmission.auto : LiveGuestAdmission.approve;

/// The room's share link (`policy.link`, `POST/GET …/link`).
class LiveLink {
  const LiveLink({
    required this.url,
    required this.token,
    this.canPublish = false,
    this.maxGuests,
    this.hasPin = false,
    this.createdAt,
  });

  final String url;
  final String token;
  final bool canPublish;
  final int? maxGuests;
  final bool hasPin;
  final DateTime? createdAt;

  factory LiveLink.fromJson(Map<String, dynamic> j) => LiveLink(
        url: '${j['url'] ?? ''}',
        token: '${j['token'] ?? ''}',
        canPublish: j['can_publish'] == true,
        maxGuests: (j['max_guests'] as num?)?.toInt(),
        hasPin: j['has_pin'] == true,
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      );
}

class LivePolicy {
  const LivePolicy({
    required this.ref,
    this.admission = LiveAdmission.open,
    this.guestAdmission = LiveGuestAdmission.approve,
    this.waiting = 0,
    this.link,
  });

  final LiveRoomRef ref;
  final LiveAdmission admission;
  final LiveGuestAdmission guestAdmission;
  final int waiting;
  final LiveLink? link;

  bool get everyoneNeedsApproval => admission == LiveAdmission.approve;

  bool get guestsJoinAutomatically => guestAdmission == LiveGuestAdmission.auto;

  factory LivePolicy.fromJson(Map<String, dynamic> j, {LiveRoomRef? fallback}) {
    final link = j['link'];
    return LivePolicy(
      ref: LiveRoomRef.parse(j['kind'], j['id']) ?? fallback ?? const LiveRoomRef.session(0),
      admission: liveAdmissionFrom(j['admission']),
      guestAdmission: liveGuestAdmissionFrom(j['guest_admission']),
      waiting: (j['waiting'] as num?)?.toInt() ?? 0,
      link: link is Map ? LiveLink.fromJson(Map<String, dynamic>.from(link)) : null,
    );
  }

  LivePolicy copyWith({LiveAdmission? admission, LiveGuestAdmission? guestAdmission, int? waiting, LiveLink? link, bool clearLink = false}) =>
      LivePolicy(
        ref: ref,
        admission: admission ?? this.admission,
        guestAdmission: guestAdmission ?? this.guestAdmission,
        waiting: waiting ?? this.waiting,
        link: clearLink ? null : (link ?? this.link),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Lobby
// ─────────────────────────────────────────────────────────────────────────────

/// One person waiting at the door (`GET …/lobby → waiting[]`, and the push `live_join_request`).
class LobbyRequest {
  const LobbyRequest({
    required this.id,
    required this.name,
    this.isGuest = false,
    this.userId,
    this.imageUrl,
    this.requestedAt,
  });

  /// `request_id` as the server sends it (kept as text: it goes straight back into the admit / reject path).
  final String id;
  final String name;
  final bool isGuest;
  final int? userId;
  final String? imageUrl;
  final DateTime? requestedAt;

  factory LobbyRequest.fromJson(Map<String, dynamic> j) {
    final img = '${j['image_url'] ?? ''}'.trim();
    return LobbyRequest(
      id: '${j['request_id'] ?? j['id'] ?? ''}',
      name: '${j['name'] ?? ''}'.trim(),
      isGuest: '${j['kind'] ?? j['request_kind'] ?? 'member'}' == 'guest',
      userId: int.tryParse('${j['user_id'] ?? ''}'),
      imageUrl: img.isEmpty ? null : img,
      requestedAt: DateTime.tryParse('${j['requested_at'] ?? j['created_at'] ?? ''}'),
    );
  }

  /// A readable name even when the server sent none.
  String get displayName => name.trim().isEmpty ? (isGuest ? t('زائر', 'Guest') : t('عضو', 'Member')) : name.trim();
}

/// `GET …/lobby`.
class LobbyState {
  const LobbyState({
    this.waiting = const [],
    this.admission = LiveAdmission.open,
    this.guestAdmission = LiveGuestAdmission.approve,
    this.admittedRecent = const [],
  });

  final List<LobbyRequest> waiting;
  final LiveAdmission admission;
  final LiveGuestAdmission guestAdmission;
  final List<LobbyRequest> admittedRecent;

  factory LobbyState.fromJson(Map<String, dynamic> j) => LobbyState(
        waiting: _requests(j['waiting']),
        admission: liveAdmissionFrom(j['admission']),
        guestAdmission: liveGuestAdmissionFrom(j['guest_admission']),
        admittedRecent: _requests(j['admitted_recent']),
      );

  static List<LobbyRequest> _requests(dynamic v) => [
        for (final e in (v as List? ?? const [])) if (e is Map) LobbyRequest.fromJson(Map<String, dynamic>.from(e)),
      ];
}

/// The ids in [now] that were not in [before] — the lobby controller plays the sound and shows the banner for these.
List<LobbyRequest> newLobbyRequests(List<LobbyRequest> before, List<LobbyRequest> now) {
  final seen = {for (final r in before) r.id};
  return [for (final r in now) if (!seen.contains(r.id)) r];
}

// ─────────────────────────────────────────────────────────────────────────────
// Join outcome
// ─────────────────────────────────────────────────────────────────────────────

enum JoinStatus { admitted, waiting, rejected, expired }

class JoinOutcome {
  const JoinOutcome._(this.status, {this.payload = const {}, this.requestId, this.secret, this.pollAfter = const Duration(seconds: 3)});

  const JoinOutcome.admitted(Map<String, dynamic> payload) : this._(JoinStatus.admitted, payload: payload);

  const JoinOutcome.waiting({required String requestId, String? secret, Duration pollAfter = const Duration(seconds: 3)})
      : this._(JoinStatus.waiting, requestId: requestId, secret: secret, pollAfter: pollAfter);

  const JoinOutcome.rejected() : this._(JoinStatus.rejected);

  const JoinOutcome.expired() : this._(JoinStatus.expired);

  final JoinStatus status;

  /// The join payload (url / ws_url, token, room, identity, can_publish, ttl_seconds…) when [isAdmitted].
  final Map<String, dynamic> payload;

  /// Lobby request to poll while [isWaiting]; [secret] only on the public (guest) flow.
  final String? requestId;
  final String? secret;
  final Duration pollAfter;

  bool get isAdmitted => status == JoinStatus.admitted;

  bool get isWaiting => status == JoinStatus.waiting;

  /// Rejected or expired: the joiner is told and sent back.
  bool get isRefused => status == JoinStatus.rejected || status == JoinStatus.expired;

  /// 200 `{status: admitted, …}` / today's plain join payload → admitted; 202 `{status: waiting, request_id,
  /// secret?, poll_after}` → waiting; the poll's `rejected` / `expired`. Never throws.
  static JoinOutcome parse(dynamic body) {
    final map = ApiException.asMap(body);
    if (map == null) return const JoinOutcome.admitted({});
    final j = Map<String, dynamic>.from(map);
    final status = '${j['status'] ?? ''}'.trim().toLowerCase();
    switch (status) {
      case 'waiting':
      case 'pending':
        final sec = '${j['secret'] ?? ''}';
        final after = (j['poll_after'] as num?)?.toInt() ?? 3;
        return JoinOutcome.waiting(
          requestId: '${j['request_id'] ?? j['id'] ?? ''}',
          secret: sec.isEmpty ? null : sec,
          pollAfter: Duration(seconds: after.clamp(1, 30)),
        );
      case 'rejected':
      case 'denied':
        return const JoinOutcome.rejected();
      case 'expired':
        return const JoinOutcome.expired();
    }
    return JoinOutcome.admitted(j);
  }

  /// Signalling URL: `url` (meetings) or `ws_url` (sessions).
  String get url => '${payload['url'] ?? payload['ws_url'] ?? ''}';

  String get token => '${payload['token'] ?? ''}';

  bool get canPublish => payload['can_publish'] != false;

  bool get recordingEnabled => payload['recording_enabled'] != false;

  String? get identity {
    final v = '${payload['identity'] ?? ''}';
    return v.isEmpty ? null : v;
  }

  /// The room credentials for PreJoinPage / RoomPage; [sessionId] is the room screen's id (negative for meetings).
  LiveResponseModel live({required int sessionId}) =>
      LiveResponseModel(sessionId: sessionId, url: url, token: token, recordingEnabled: recordingEnabled);
}

// ─────────────────────────────────────────────────────────────────────────────
// Silent push → the room
// ─────────────────────────────────────────────────────────────────────────────

/// `live_join_request` pushes (`{kind, id, request_id, name}`) land here; the host's room refreshes its lobby at once.
class LiveLobbyEvents {
  LiveLobbyEvents._();

  /// The latest push payload (null until the first one). Set again even when equal: listeners compare nothing.
  static final ValueNotifier<Map<String, dynamic>?> latest = ValueNotifier<Map<String, dynamic>?>(null);

  static const String pushType = 'live_join_request';

  static void notify(Map<String, dynamic> data) {
    latest.value = null; // re-fire even when the same request is pushed twice
    latest.value = Map<String, dynamic>.from(data);
  }

  /// The room the push is about (null when it carries no kind / id).
  static LiveRoomRef? refOf(Map<String, dynamic>? data) => data == null ? null : LiveRoomRef.parse(data['kind'], data['id']);
}

// ─────────────────────────────────────────────────────────────────────────────
// Error codes → text
// ─────────────────────────────────────────────────────────────────────────────

/// Bilingual text for the live-room server codes; falls back to the ApiException message.
String liveRoomErrorText(Object e) {
  final ex = ApiException.from(e);
  final text = liveRoomCodeText(ex.code);
  if (text != null) return text;
  if (ex.statusCode == 429) return t('محاولات كثيرة — انتظر دقيقة ثم أعد المحاولة.', 'Too many attempts — wait a minute and try again.');
  return ex.message;
}

/// Null for a code this file does not know.
String? liveRoomCodeText(String? code) => switch (code) {
      'not_host' || 'host_only' => t('هذا الإجراء لمضيف الغرفة فقط.', 'Only the room host can do this.'),
      'room_not_found' || 'live_room_not_found' || 'meeting_not_found' || 'session_not_found' =>
        t('الغرفة غير موجودة.', 'This room does not exist.'),
      'invalid_kind' || 'wrong_kind' => t('نوع الغرفة غير معروف.', 'Unknown room kind.'),
      'request_not_found' => t('طلب الانضمام غير موجود أو انتهى.', 'This join request no longer exists.'),
      'request_expired' || 'join_expired' => t('انتهت مهلة طلب الانضمام. اطلب الانضمام مرة أخرى.', 'The join request expired. Ask to join again.'),
      'request_rejected' || 'join_rejected' => t('لم يسمح المضيف بالانضمام.', 'The host did not let you in.'),
      'already_decided' => t('بُتّ في هذا الطلب من قبل.', 'This request was already decided.'),
      'not_invited' || 'not_member' || 'not_enrolled' => t('أنت لست من أعضاء هذه الغرفة.', 'You are not a member of this room.'),
      'live_not_started' => t('لم يبدأ البث بعد.', 'The room has not started yet.'),
      'live_ended' || 'meeting_ended' => t('انتهت هذه الجلسة.', 'This room has ended.'),
      'link_missing' || 'guest_link_missing' => t('لا يوجد رابط مشاركة لهذه الغرفة.', 'This room has no share link.'),
      'link_invalid' || 'guest_link_invalid' => t('هذا الرابط غير صالح.', 'This link is not valid.'),
      'guests_disabled' => t('روابط الزوار غير متاحة.', 'Share links are switched off.'),
      'guest_limit_reached' => t('اكتمل عدد الزوار المسموح به.', 'The guest limit of this link was reached.'),
      'guest_pin_invalid' => t('رمز الدخول غير صحيح.', 'Wrong PIN.'),
      'guest_pin_required' => t('هذا الرابط يحتاج رمز دخول.', 'This link needs a PIN.'),
      'guest_pin_format' => t('رمز الدخول من 4 إلى 8 أرقام.', 'The PIN is 4–8 digits.'),
      'consent_required' => t('يجب الموافقة قبل الانضمام.', 'You have to agree before joining.'),
      'lobby_disabled' => t('غرفة الانتظار غير متاحة.', 'The lobby is switched off.'),
      'too_many_requests' => t('محاولات كثيرة — انتظر دقيقة ثم أعد المحاولة.', 'Too many attempts — wait a minute and try again.'),
      _ => null,
    };

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

/// Host calls on one room (policy · share link · lobby) and the joiner's static calls. Every path is written out so
/// the API contract scan (test/contract/) can read it.
class LiveRoomApi {
  LiveRoomApi(this.ref, {ApiClient? api}) : _api = api ?? ApiClient();

  final LiveRoomRef ref;
  final ApiClient _api;

  String get _kind => ref.kindName;

  int get _id => ref.id;

  Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};

  // ── Policy ────────────────────────────────────────────────────────────────

  Future<LivePolicy> policy() async =>
      LivePolicy.fromJson(_map(await _api.get('/api/v1/live/$_kind/$_id/policy')), fallback: ref);

  /// Only the fields given are changed. Switching to `open` / `auto` admits everyone waiting under that rule.
  Future<LivePolicy> setPolicy({LiveAdmission? admission, LiveGuestAdmission? guestAdmission}) async =>
      LivePolicy.fromJson(
        _map(await _api.put('/api/v1/live/$_kind/$_id/policy', body: {
          if (admission != null) 'admission': admission.name,
          if (guestAdmission != null) 'guest_admission': guestAdmission.name,
        })),
        fallback: ref,
      );

  // ── Share link ────────────────────────────────────────────────────────────

  /// Creates the link or changes its options; a new PIN replaces the old one, null keeps it.
  Future<LiveLink> createLink({required bool canPublish, int? maxGuests, String? pin}) async {
    final r = _map(await _api.post('/api/v1/live/$_kind/$_id/link', body: {
      'can_publish': canPublish,
      'max_guests': maxGuests,
      'pin': (pin == null || pin.isEmpty) ? null : pin,
    }));
    // The server answers `policy.link`, either bare or wrapped in the policy.
    final link = r['link'];
    return LiveLink.fromJson(link is Map ? Map<String, dynamic>.from(link) : r);
  }

  /// The current link, or null when none exists (404).
  Future<LiveLink?> link() async {
    try {
      final r = _map(await _api.get('/api/v1/live/$_kind/$_id/link'));
      if (r.isEmpty || '${r['url'] ?? r['token'] ?? ''}'.isEmpty) return null;
      return LiveLink.fromJson(r);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> deleteLink() => _api.delete('/api/v1/live/$_kind/$_id/link');

  // ── Lobby ─────────────────────────────────────────────────────────────────

  Future<LobbyState> lobby() async => LobbyState.fromJson(_map(await _api.get('/api/v1/live/$_kind/$_id/lobby')));

  Future<void> admit(String requestId) => _api.post('/api/v1/live/$_kind/$_id/lobby/${Uri.encodeComponent(requestId)}/admit');

  Future<void> reject(String requestId) => _api.post('/api/v1/live/$_kind/$_id/lobby/${Uri.encodeComponent(requestId)}/reject');

  Future<void> admitAll() => _api.post('/api/v1/live/$_kind/$_id/lobby/admit-all');

  // ── Joiner ────────────────────────────────────────────────────────────────

  /// A signed-in member's own request (`GET /api/v1/live/requests/{id}`).
  static Future<JoinOutcome> pollRequest(String requestId, {ApiClient? api}) async =>
      JoinOutcome.parse(await (api ?? ApiClient()).get('/api/v1/live/requests/${Uri.encodeComponent(requestId)}'));

  /// A guest's request (`GET /api/v1/public/live/requests/{id}?secret=…`, no token).
  static Future<JoinOutcome> pollPublicRequest(String requestId, {String? secret, ApiClient? api}) async =>
      JoinOutcome.parse(await (api ?? ApiClient()).get(
        '/api/v1/public/live/requests/${Uri.encodeComponent(requestId)}',
        queryParams: {if (secret != null && secret.isNotEmpty) 'secret': secret},
        auth: false,
      ));

  /// The poll that fits the outcome: public when it carries a secret (guest), else the member one.
  static Future<JoinOutcome> poll(JoinOutcome waiting, {ApiClient? api}) {
    final id = waiting.requestId ?? '';
    return waiting.secret != null ? pollPublicRequest(id, secret: waiting.secret, api: api) : pollRequest(id, api: api);
  }

  /// A signed-in person opening a share link (`POST /api/v1/live/links/{token}/join`): a member joins under the
  /// member rule, anyone else as a named guest under the guest rule. Same two answers as the public join.
  static Future<JoinOutcome> joinLink(String token, {ApiClient? api}) async =>
      JoinOutcome.parse(await (api ?? ApiClient()).post('/api/v1/live/links/${Uri.encodeComponent(token)}/join'));
}
