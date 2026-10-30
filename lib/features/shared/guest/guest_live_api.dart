// lib/features/shared/guest/guest_live_api.dart
//
// Guest links for live sessions: a teacher creates one public link per live session, anyone with the link
// joins the LiveKit room by typing a name — no account, no token.
//
//   Teacher (auth):   POST/GET/DELETE /api/v1/live-sessions/{id}/guest-link       → GuestLinkApi
//                     GET /api/v1/live-sessions/{id}/guest-link/joins?limit=100  → GuestLinkApi.joins
//   Public (no auth): GET  /api/v1/public/live/{token}                           → GuestLiveApi.info
//                     POST /api/v1/public/live/{token}/join {name, pin?}         → GuestLiveApi.join
//
// A link may carry a PIN (4–8 digits: `pin` / `clear_pin` on POST, `has_pin` back; `requires_pin` on the public
// GET; a wrong one answers 403 `guest_pin_invalid`). The public routes are rate limited per IP: 429
// `too_many_requests` → the page waits a minute before letting the visitor try again.
//
// Public calls are sent with `auth: false`, so ApiClient neither attaches a token nor redirects to the login
// screen on a 401. Server codes (ApiException.code) are turned into bilingual text by [guestLiveErrorText].
// The pure helpers at the bottom ([guestLiveTokenFromRoute], [guestLiveRouteFromUri]) are what main.dart uses
// to resolve `/live/<token>` as a route (web path, web hash and app links).
import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../live/live_controls_api.dart' show liveControlsErrorText;
import '../live/live_room.dart'
    show JoinOutcome, LiveGuestAdmission, LiveRoomKind, LiveRoomRef, liveGuestAdmissionFrom, liveRoomCodeText;
import '../live/live_room_words.dart' show liveTr;
import '../live/live_config.dart';
import '../live/live_time_limit.dart' show parseLiveTimeLimit, parseNaiveUtc;

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// The teacher's view of a session's guest link.
class GuestLink {
  const GuestLink({
    required this.url,
    required this.token,
    required this.canPublish,
    required this.maxGuests,
    required this.guestsJoined,
    this.createdAt,
    this.hasPin = false,
  });

  final String url;
  final String token;
  final bool canPublish;
  final int? maxGuests;
  final int guestsJoined;
  final DateTime? createdAt;

  /// Visitors must type a PIN (the PIN itself is never sent back).
  final bool hasPin;

  factory GuestLink.fromJson(Map<String, dynamic> j) => GuestLink(
        url: (j['url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        canPublish: j['can_publish'] == true,
        maxGuests: (j['max_guests'] as num?)?.toInt(),
        guestsJoined: (j['guests_joined'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
        hasPin: j['has_pin'] == true,
      );
}

/// One visitor who joined through the link (GET …/guest-link/joins).
class GuestJoinRecord {
  const GuestJoinRecord({required this.identity, required this.name, this.joinedAt, this.ipMasked});

  final String identity;
  final String name;
  final DateTime? joinedAt;

  /// e.g. `41.33.xx.xx` — the server never sends the full address.
  final String? ipMasked;

  factory GuestJoinRecord.fromJson(Map<String, dynamic> j) {
    final ip = (j['ip_masked'] ?? '').toString().trim();
    return GuestJoinRecord(
      identity: (j['identity'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      joinedAt: DateTime.tryParse(j['joined_at']?.toString() ?? ''),
      ipMasked: ip.isEmpty ? null : ip,
    );
  }
}

/// `{items, total}` of GET …/guest-link/joins.
class GuestJoinsPage {
  const GuestJoinsPage({required this.items, required this.total});

  final List<GuestJoinRecord> items;
  final int total;

  factory GuestJoinsPage.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => GuestJoinRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return GuestJoinsPage(items: items, total: (j['total'] as num?)?.toInt() ?? items.length);
  }
}

/// `true` for a well-formed PIN: 4–8 digits.
bool guestPinValid(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin.trim());

/// What a visitor sees before joining (GET /public/live/{token}). A link now points at a course live session OR a
/// calendar meeting (live-rooms-spec §3): `kind`, `title`, `host_name`, `starts_at`, `guest_admission` and
/// `signed_in_join` were added to the payload; the session fields keep working for older servers.
class GuestLiveInfo {
  const GuestLiveInfo({
    required this.sessionId,
    required this.sessionName,
    required this.courseName,
    required this.teacherName,
    required this.isLive,
    required this.canPublish,
    required this.recordingEnabled,
    required this.guestsJoined,
    required this.maxGuests,
    this.requiresPin = false,
    this.kind = 'session',
    this.title = '',
    this.hostName = '',
    this.startsAt,
    this.guestAdmission = LiveGuestAdmission.approve,
    this.signedInJoin = false,
    this.meetingId,
    this.autoJoin = false,
  });

  final int sessionId;
  final String sessionName;
  final String courseName;
  final String teacherName;
  final bool isLive;
  final bool canPublish;
  final bool recordingEnabled;
  final int guestsJoined;
  final int? maxGuests;

  /// The visitor must type the link's PIN to join.
  final bool requiresPin;

  /// `session` | `meeting`.
  final String kind;

  /// The room's title (`title`, else the session name).
  final String title;

  /// Who hosts it (`host_name`, else the teacher name).
  final String hostName;

  /// Meetings: when it starts (UTC).
  final DateTime? startsAt;

  /// `approve` → visitors wait for the host; `auto` → straight in.
  final LiveGuestAdmission guestAdmission;

  /// The server offers `POST /api/v1/live/links/{token}/join` to a signed-in viewer.
  final bool signedInJoin;

  /// `meeting_id` (or `id`) when [kind] is `meeting`.
  final int? meetingId;

  /// `auto_join` (spec §10): the link is DIRECT — a signed-in viewer joins with the account at once, a remembered
  /// guest name joins at once, otherwise only the name field is asked; the pre-join step then presses Join itself.
  final bool autoJoin;

  bool get isMeeting => kind == 'meeting';

  /// The room, for JoinArgs.roomRef / RoomPage (a meeting room keeps the `-meetingId` convention).
  LiveRoomRef get ref => isMeeting ? LiveRoomRef.meeting(meetingId ?? sessionId) : LiveRoomRef.session(sessionId);

  /// The title to show (`title`, else the session name).
  String get displayTitle => title.trim().isNotEmpty ? title.trim() : sessionName.trim();

  /// The host to show (`host_name`, else the teacher name).
  String get displayHost => hostName.trim().isNotEmpty ? hostName.trim() : teacherName.trim();

  factory GuestLiveInfo.fromJson(Map<String, dynamic> j) {
    final kind = '${j['kind'] ?? 'session'}'.trim().toLowerCase();
    return GuestLiveInfo(
      sessionId: (j['session_id'] as num?)?.toInt() ?? (kind == 'meeting' ? 0 : (j['id'] as num?)?.toInt() ?? 0),
      sessionName: (j['session_name'] ?? '').toString(),
      courseName: (j['course_name'] ?? '').toString(),
      teacherName: (j['teacher_name'] ?? '').toString(),
      isLive: j['is_live'] == true,
      canPublish: j['can_publish'] == true,
      recordingEnabled: j['recording_enabled'] == true,
      guestsJoined: (j['guests_joined'] as num?)?.toInt() ?? 0,
      maxGuests: (j['max_guests'] as num?)?.toInt(),
      requiresPin: j['requires_pin'] == true,
      kind: kind == 'meeting' ? 'meeting' : 'session',
      title: (j['title'] ?? '').toString(),
      hostName: (j['host_name'] ?? '').toString(),
      startsAt: DateTime.tryParse('${j['starts_at'] ?? ''}')?.toUtc(),
      guestAdmission: liveGuestAdmissionFrom(j['guest_admission']),
      signedInJoin: j['signed_in_join'] == true,
      meetingId: kind == 'meeting' ? ((j['meeting_id'] ?? j['id']) as num?)?.toInt() : null,
      autoJoin: j['auto_join'] == true,
    );
  }
}

/// The room credentials a guest gets back from POST /public/live/{token}/join.
class GuestJoin {
  const GuestJoin({
    required this.wsUrl,
    required this.token,
    required this.sessionId,
    required this.canPublish,
    required this.recordingEnabled,
    required this.identity,
    this.freeEndsAt,
    this.liveStartedAt,
    this.liveConfig = LiveConfig.defaults,
  });

  final String wsUrl;
  final String token;
  final int sessionId;
  final bool canPublish;
  final bool recordingEnabled;
  final String identity;

  /// A student meeting's free-time end (`time_limit.ends_at`, UTC), null = unlimited (spec §8).
  final DateTime? freeEndsAt;

  /// When the room went live (`live_started_at`, UTC; spec §16), null when not sent.
  final DateTime? liveStartedAt;

  /// The super admin's live media settings (`live_config`, D-090), or the defaults.
  final LiveConfig liveConfig;

  factory GuestJoin.fromJson(Map<String, dynamic> j) => GuestJoin(
        wsUrl: (j['ws_url'] ?? j['url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        sessionId: (j['session_id'] as num?)?.toInt() ?? 0,
        canPublish: j['can_publish'] != false,
        recordingEnabled: j['recording_enabled'] == true,
        identity: (j['identity'] ?? '').toString(),
        freeEndsAt: parseLiveTimeLimit(j['time_limit']),
        liveStartedAt: parseNaiveUtc(j['live_started_at']),
        liveConfig: LiveConfig.fromPayload(j),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Teacher API
// ─────────────────────────────────────────────────────────────────────────────

class GuestLinkApi {
  GuestLinkApi._();

  static String _path(int sessionId) => '/api/v1/live-sessions/$sessionId/guest-link';

  /// The session's current link, or null when none exists (404 `guest_link_missing`).
  static Future<GuestLink?> load(int sessionId) async {
    try {
      final r = await ApiClient().get(_path(sessionId));
      if (r is Map<String, dynamic>) return GuestLink.fromJson(r);
      return null;
    } on ApiException catch (e) {
      if (e.code == 'guest_link_missing' || e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Creates the link, changes its options (`rotate: false` keeps the URL) or mints a new URL (`rotate: true`).
  /// [pin] sets a new PIN (4–8 digits), null keeps the current one; [clearPin] removes it.
  static Future<GuestLink> save(
    int sessionId, {
    required bool canPublish,
    required int? maxGuests,
    bool rotate = false,
    String? pin,
    bool clearPin = false,
  }) async {
    final r = await ApiClient().post(_path(sessionId), body: {
      'can_publish': canPublish,
      'max_guests': maxGuests,
      'rotate': rotate,
      'pin': clearPin ? null : pin,
      'clear_pin': clearPin,
    });
    return GuestLink.fromJson(Map<String, dynamic>.from(r as Map));
  }

  static Future<void> revoke(int sessionId) => ApiClient().delete(_path(sessionId));

  /// Who joined through the link (newest first), [limit] rows at most.
  static Future<GuestJoinsPage> joins(int sessionId, {int limit = 100}) async {
    final r = await ApiClient().get('${_path(sessionId)}/joins', queryParams: {'limit': limit});
    return GuestJoinsPage.fromJson(Map<String, dynamic>.from(r as Map));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API (no auth)
// ─────────────────────────────────────────────────────────────────────────────

class GuestLiveApi {
  GuestLiveApi._();

  static Future<GuestLiveInfo> info(String token) async {
    final r = await ApiClient().get('/api/v1/public/live/$token', auth: false);
    return GuestLiveInfo.fromJson(Map<String, dynamic>.from(r as Map));
  }

  /// `POST …/join {name, pin?, consent: true}` → 200 admitted (the join payload: `GuestJoin.fromJson(outcome.payload)`)
  /// or 202 waiting (`request_id`, `secret`, `poll_after`) — the page then polls
  /// `GET /api/v1/public/live/requests/{id}?secret=` (LiveRoomApi.pollPublicRequest) until the host decides.
  static Future<JoinOutcome> join(String token, String name, {String? pin}) async {
    final r = await ApiClient().post(
      '/api/v1/public/live/$token/join',
      body: {'name': name, if (pin != null && pin.isNotEmpty) 'pin': pin, 'consent': true},
      auth: false,
    );
    return JoinOutcome.parse(r);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error codes → text
// ─────────────────────────────────────────────────────────────────────────────

/// Bilingual text for the guest-link server codes; falls back to the ApiException message. [kind]: the link's room
/// when known — a meeting's texts say «الاجتماع» (D-106).
String guestLiveErrorText(Object e, {LiveRoomKind? kind}) {
  final ex = ApiException.from(e);
  final k = kind ?? LiveRoomKind.session;
  switch (ex.code) {
    case 'guest_link_invalid':
      return 'guest_live_err_invalid'.tr;
    case 'guest_link_missing':
      return liveTr('guest_live_err_missing', k);
    case 'live_not_started':
      return liveTr('guest_live_err_not_started', k);
    case 'live_ended':
      return liveTr('guest_live_err_ended', k);
    case 'guest_limit_reached':
      return liveTr('guest_live_err_limit', k);
    case 'guests_disabled':
      return liveTr('guest_live_err_disabled', k);
    case 'guest_pin_invalid':
      return liveTr('guest_live_err_pin', k);
    case 'guest_pin_required':
      return 'guest_live_pin_required'.tr;
    case 'guest_pin_format':
      return 'guest_link_pin_invalid'.tr;
    case 'too_many_requests':
      return 'guest_live_err_rate_limited'.tr;
    case 'guest_blocked':
      return liveTr('guest_live_err_blocked', k);
    // The host's controls (live hardening): 423 room_locked, 403 participant_removed.
    case 'room_locked':
    case 'participant_removed':
      return liveControlsErrorText(ex.code, kind: k)!;
  }
  if (ex.statusCode == 423) return liveControlsErrorText('room_locked', kind: k)!;
  if (ex.statusCode == 429) return 'guest_live_err_rate_limited'.tr;
  return liveRoomErrorTextOrNull(ex, kind: k) ?? ex.message;
}

/// The live-room codes (lobby, requests, meetings) that the guest page can also meet — null when unknown.
String? liveRoomErrorTextOrNull(ApiException ex, {LiveRoomKind? kind}) => liveRoomCodeText(ex.code, kind: kind);

/// 429 / `too_many_requests`: the visitor has to wait a minute before trying again.
bool guestLiveErrorIsRateLimit(Object e) {
  final ex = ApiException.from(e);
  return ex.code == 'too_many_requests' || ex.statusCode == 429;
}

/// 403 `guest_pin_invalid`: the PIN field shows its error and shakes.
bool guestLiveErrorIsPin(Object e) => ApiException.from(e).code == 'guest_pin_invalid';

/// True when the error means the link itself is dead: polling it again is pointless.
bool guestLiveErrorIsFinal(Object e) {
  final code = ApiException.from(e).code;
  return code == 'guest_link_invalid' ||
      code == 'live_ended' ||
      code == 'guests_disabled' ||
      // The host removed / blocked this visitor: asking again never lets them in (a locked room may open again).
      code == 'participant_removed' ||
      code == 'guest_blocked';
}

// ─────────────────────────────────────────────────────────────────────────────
// Route helpers (pure)
// ─────────────────────────────────────────────────────────────────────────────

/// `/live/<token>` (or a full URL whose path or hash is that) → token, else null.
String? guestLiveTokenFromRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return null;
  final uri = Uri.tryParse(routeName);
  if (uri == null) return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length == 2 && seg[0] == 'live' && seg[1].trim().isNotEmpty) {
    return Uri.decodeComponent(seg[1].trim());
  }
  return null;
}

/// The guest route a browser URL points at — path form `/live/x` or the legacy hash form `/#/live/x` — else null.
String? guestLiveRouteFromUri(Uri base) {
  final fromPath = guestLiveTokenFromRoute(base.path);
  final fromHash = guestLiveTokenFromRoute(base.fragment);
  final token = fromPath ?? fromHash;
  return token == null ? null : '/live/$token';
}

/// The web app uses the path URL strategy, so `/live/x`, `/c/12?ref=5` and `/dashboard` are real paths that
/// Flutter itself hands over as the first route. Links from before the switch — `/#/live/x`, `/#/dashboard` —
/// carry the route in the hash instead: this returns that route (path + its own query) when the fragment holds
/// one, else null. main.dart starts on it and rewrites the browser URL to the clean path.
String? legacyHashRoute(Uri base) {
  final frag = base.fragment;
  if (frag.length < 2 || !frag.startsWith('/')) return null;
  final uri = Uri.tryParse(frag);
  if (uri == null || uri.path.isEmpty || uri.path == '/') return null;
  return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
}
